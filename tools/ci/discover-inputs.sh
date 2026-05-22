#!/usr/bin/env bash
# discover-inputs.sh — list upstream GitHub releases that ship rom.zip.
#
# Usage:
#   ./tools/ci/discover-inputs.sh [--source-repo OWNER/NAME] [--force]
#
# Writes JSON array to stdout (GHA matrix "include" entries).

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

Only assets named exactly "rom.zip" are included.
Repos scanned: y1-community/y1-stock-rom, rockbox-y1/rockbox
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
import json, subprocess, sys

source_filter = sys.argv[1]
force = sys.argv[2] == "true"
repos = sys.argv[3:]

def slug_for_repo(full_name: str) -> str:
    if full_name == "y1-community/y1-stock-rom":
        return "y1-stock-rom"
    if full_name == "rockbox-y1/rockbox":
        return "rockbox"
    return full_name.split("/")[-1]

entries = []

for repo in repos:
    if source_filter and repo != source_filter:
        continue
    slug_base = slug_for_repo(repo)
    out = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases", "--paginate"],
        capture_output=True,
        text=True,
        check=True,
    )
    releases = json.loads(out.stdout)
    for rel in releases:
        if rel.get("draft"):
            continue
        tag = rel["tag_name"]
        for asset in rel.get("assets") or []:
            if asset.get("name") != "rom.zip":
                continue
            digest = asset.get("digest") or ""
            if digest.startswith("sha256:"):
                digest = digest[7:]
            release_tag = f"{slug_base}@{tag}"
            entries.append({
                "source_repo": repo,
                "source_tag": tag,
                "release_tag": release_tag,
                "download_url": asset["browser_download_url"],
                "digest": digest,
                "slug": release_tag.replace("@", "-"),
                "force": force,
            })

print(json.dumps(entries))
PY
