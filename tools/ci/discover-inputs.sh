#!/usr/bin/env bash
# discover-inputs.sh — build matrix for allowed upstream rom.zip releases.
#
# Only these upstream tags are considered (no open-ended gh release scan):
#   y1-community/y1-stock-rom  → tags 3.0.2, Latest-3.0.7 (firmware 3.0.7)
#   rockbox-y1/rockbox         → stable-v0.5 and later stable-v* tags
#
# Usage:
#   ./tools/ci/discover-inputs.sh [--source-repo OWNER/NAME] [--force]

set -euo pipefail

SOURCE_FILTER=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-repo)
      SOURCE_FILTER="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./tools/ci/discover-inputs.sh [--source-repo OWNER/NAME] [--force]

Emits a JSON array of matrix objects:
  source_repo, source_tag, release_tag, download_url, digest, slug

Upstream allowlist (rom.zip only):
  y1-community/y1-stock-rom: 3.0.2, Latest-3.0.7 (→ koensayr release y1-stock-rom@3.0.7)
  rockbox-y1/rockbox:        stable-v0.5 and newer stable-v* releases
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg $1" >&2
      exit 1
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 required" >&2
  exit 1
fi

REPOS=(
  "y1-community/y1-stock-rom"
  "rockbox-y1/rockbox"
)

python3 - "$SOURCE_FILTER" "$FORCE" "${REPOS[@]}" <<'PY'
import json
import subprocess
import sys

source_filter = sys.argv[1]
force = sys.argv[2] == "true"
repos = sys.argv[3:]

Y1_REPO = "y1-community/y1-stock-rom"
ROCKBOX_REPO = "rockbox-y1/rockbox"
# Upstream GitHub release tag → firmware version for koensayr release naming.
Y1_UPSTREAM_TAGS = {
    "3.0.2": "3.0.2",
    "Latest-3.0.7": "3.0.7",
}
ROCKBOX_MIN_STABLE = (0, 5, 0)


def slug_for_repo(full_name: str) -> str:
    if full_name == Y1_REPO:
        return "y1-stock-rom"
    if full_name == ROCKBOX_REPO:
        return "rockbox"
    return full_name.split("/")[-1]


def parse_stable_v(tag: str) -> tuple[int, ...] | None:
    if not tag.startswith("stable-v"):
        return None
    rest = tag[len("stable-v") :]
    parts: list[int] = []
    for part in rest.split("."):
        if not part.isdigit():
            return None
        parts.append(int(part))
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def tag_allowed(repo: str, tag: str) -> bool:
    if repo == Y1_REPO:
        return tag in Y1_UPSTREAM_TAGS
    if repo == ROCKBOX_REPO:
        ver = parse_stable_v(tag)
        return ver is not None and ver >= ROCKBOX_MIN_STABLE
    return False


def upstream_release_tags(repo: str) -> list[str]:
    """Tag names from gh release list (JSON array, not paginated NDJSON)."""
    out = subprocess.run(
        ["gh", "release", "list", "--repo", repo, "--limit", "200", "--json", "tagName"],
        capture_output=True,
        text=True,
        check=True,
    )
    if not out.stdout.strip():
        return []
    releases = json.loads(out.stdout)
    return [r["tagName"] for r in releases if r.get("tagName")]


def tags_to_probe(repo: str) -> list[str]:
    if repo == Y1_REPO:
        return sorted(
            Y1_UPSTREAM_TAGS.keys(),
            key=lambda t: Y1_UPSTREAM_TAGS[t],
        )
    if repo == ROCKBOX_REPO:
        tags = upstream_release_tags(repo)
        allowed = [t for t in tags if tag_allowed(repo, t)]
        return sorted(allowed, key=lambda t: parse_stable_v(t) or ())
    return []


def release_has_rom_zip(repo: str, tag: str) -> dict | None:
    out = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{repo}/releases/tags/{tag}",
            "--jq",
            '[.assets[] | select(.name == "rom.zip")][0]',
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if out.returncode != 0 or not out.stdout.strip() or out.stdout.strip() == "null":
        return None
    try:
        asset = json.loads(out.stdout)
    except json.JSONDecodeError:
        return None
    digest = asset.get("digest") or ""
    if digest.startswith("sha256:"):
        digest = digest[7:]
    return {
        "browser_download_url": asset["browser_download_url"],
        "digest": digest,
    }


entries: list[dict] = []

for repo in repos:
    if source_filter and repo != source_filter:
        continue
    slug_base = slug_for_repo(repo)
    for upstream_tag in tags_to_probe(repo):
        asset = release_has_rom_zip(repo, upstream_tag)
        if asset is None:
            continue
        if repo == Y1_REPO:
            fw_version = Y1_UPSTREAM_TAGS[upstream_tag]
            release_tag = f"{slug_base}@{fw_version}"
            slug = f"{slug_base}-{fw_version}"
            source_tag = upstream_tag
        else:
            release_tag = f"{slug_base}@{upstream_tag}"
            slug = release_tag.replace("@", "-")
            source_tag = upstream_tag
        entries.append(
            {
                "source_repo": repo,
                "source_tag": source_tag,
                "release_tag": release_tag,
                "download_url": asset["browser_download_url"],
                "digest": asset["digest"],
                "slug": slug,
                "force": force,
            }
        )

print(json.dumps(entries))
PY
