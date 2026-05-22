#!/usr/bin/env bash
# build-one.sh — download one upstream rom.zip, patch with koensayr --all, repack,
# and publish (or skip) a GitHub release on the current repo.
#
# Usage:
#   ./tools/ci/build-one.sh \
#     --source-repo y1-community/y1-stock-rom \
#     --source-tag 3.0.2 \
#     --release-tag y1-stock-rom@3.0.2 \
#     --download-url <url> \
#     --digest <sha256> \
#     --slug y1-stock-rom-3.0.2 \
#     [--force]

set -euo pipefail

SOURCE_REPO=""
SOURCE_TAG=""
RELEASE_TAG=""
DOWNLOAD_URL=""
DIGEST=""
SLUG=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-repo) SOURCE_REPO="$2"; shift 2 ;;
    --source-tag) SOURCE_TAG="$2"; shift 2 ;;
    --release-tag) RELEASE_TAG="$2"; shift 2 ;;
    --download-url) DOWNLOAD_URL="$2"; shift 2 ;;
    --digest) DIGEST="$2"; shift 2 ;;
    --slug) SLUG="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: ./tools/ci/build-one.sh --source-repo REPO --source-tag TAG \
  --release-tag TAG --download-url URL --digest SHA256 --slug SLUG [--force]

Environment:
  KOENSAYR_SKIP_PUBLISH=1   Build only; do not create/upload GitHub release.
  GITHUB_REPOSITORY          Target repo for releases (defaults from gh).
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE_REPO" || -z "$SOURCE_TAG" || -z "$RELEASE_TAG" || -z "$DOWNLOAD_URL" || -z "$SLUG" ]]; then
  echo "ERROR: --source-repo, --source-tag, --release-tag, --download-url, and --slug are required" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CI_DIR="${REPO_ROOT}/tools/ci"
WORKDIR="$(mktemp -d -t koensayr-ci.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

STAGING="${WORKDIR}/staging"
EXTRACT="${WORKDIR}/rom-extract"
mkdir -p "$STAGING" "$EXTRACT"

KOENSAYR_VERSION="$(grep -E '^# Version:' apply.bash | awk '{print $3}')"

# Idempotency: skip when release exists with matching upstream digest.
if [[ "$FORCE" != true && "${KOENSAYR_SKIP_PUBLISH:-}" != "1" ]]; then
  if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    if [[ -n "$DIGEST" ]] && gh release view "$RELEASE_TAG" --json body -q .body | grep -qF "$DIGEST"; then
      echo "[build-one] Release ${RELEASE_TAG} already published for digest ${DIGEST}; skipping."
      exit 0
    fi
  fi
fi

echo "[build-one] Downloading upstream rom.zip.."
curl -fsSL -o "${STAGING}/rom.zip" "$DOWNLOAD_URL"

echo "[build-one] Extracting upstream layout.."
"${CI_DIR}/extract-rom.sh" "${STAGING}/rom.zip" "$EXTRACT"

echo "[build-one] Patching (koensayr ${KOENSAYR_VERSION}).."
./apply.bash --all --no-flash --accept-any-firmware \
  --firmware-slug "$SLUG" \
  --artifacts-dir "$STAGING"

# apply.bash names the loop-mounted image system-${VERSION_FIRMWARE}-devel.img
# (manifest version e.g. 3.0.2, or --firmware-slug when using --accept-any-firmware).
resolve_devel_img() {
  local staging="$1" slug="$2" source_tag="$3"
  local p
  for p in \
    "${staging}/system-${slug}-devel.img" \
    "${staging}/system-${source_tag}-devel.img"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  for p in "${staging}"/system-*-devel.img; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

DEVEL_IMG="$(resolve_devel_img "$STAGING" "$SLUG" "$SOURCE_TAG" || true)"
if [[ -z "$DEVEL_IMG" || ! -f "$DEVEL_IMG" ]]; then
  echo "ERROR: expected patched system image under ${STAGING}/" >&2
  echo "       (tried system-${SLUG}-devel.img and system-${SOURCE_TAG}-devel.img)" >&2
  exit 1
fi
echo "[build-one] Using patched system image: ${DEVEL_IMG}"

OUTPUT_ROM="${WORKDIR}/rom-koensayr.zip"
"${CI_DIR}/repack-rom.sh" "$EXTRACT" "$DEVEL_IMG" "$OUTPUT_ROM"

# Copy staging rom for convenience
cp -f "$OUTPUT_ROM" "${STAGING}/rom-koensayr.zip"

MANIFEST="${WORKDIR}/build-manifest.json"
python3 - "$MANIFEST" <<PY
import json, hashlib, pathlib, sys
out = pathlib.Path(sys.argv[1])
rom = pathlib.Path("${OUTPUT_ROM}")
h = hashlib.sha256()
with rom.open("rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
data = {
    "koensayr_version": "${KOENSAYR_VERSION}",
    "source_repo": "${SOURCE_REPO}",
    "source_tag": "${SOURCE_TAG}",
    "release_tag": "${RELEASE_TAG}",
    "slug": "${SLUG}",
    "upstream_digest_sha256": "${DIGEST}",
    "output_rom_sha256": h.hexdigest(),
    "output_rom_bytes": rom.stat().st_size,
}
out.write_text(json.dumps(data, indent=2) + "\n")
print(json.dumps(data, indent=2))
PY

if [[ "${KOENSAYR_SKIP_PUBLISH:-}" == "1" ]]; then
  echo "[build-one] KOENSAYR_SKIP_PUBLISH=1 — artifacts in ${WORKDIR}"
  cp -f "$OUTPUT_ROM" "${REPO_ROOT}/rom-koensayr-${SLUG}.zip" 2>/dev/null || true
  exit 0
fi

NOTES="${WORKDIR}/release-notes.md"
cat > "$NOTES" <<EOF
# Koensayr ${RELEASE_TAG}

Patched **rom.zip** built by [koensayr-auto](https://github.com/${GITHUB_REPOSITORY:-ryan-specter/koensayr-auto}) v${KOENSAYR_VERSION}.

## Upstream

- Repository: [\`${SOURCE_REPO}\`](https://github.com/${SOURCE_REPO})
- Release tag: \`${SOURCE_TAG}\`
- Asset: \`rom.zip\`
- Upstream SHA256: \`${DIGEST}\`

## Patches (\`--all\`)

- Music-player UX (Artist→Album navigation)
- Bluetooth pairing (\`audio.conf\` / \`auto_pairing.conf\` / \`blacklist.conf\` / \`build.prop\`)
- System config (ADB debugging, bloatware removal)
- Root (\`/system/xbin/su\`, mode 06755)
- AVRCP 1.3 metadata + control + Y1Bridge

Diagnostic scripts (\`tools/dual-capture.sh\`, gdb attach, \`btlog-dump\`) are **not** included in the ROM — see the repo [Diagnostics](https://github.com/${GITHUB_REPOSITORY:-ryan-specter/koensayr-auto}#diagnostics).

## After flash

If AVRCP / MultiDex classes fail to load after upgrading from a prior koensayr build:

\`\`\`bash
adb shell rm -rf /data/data/com.innioasis.y1/code_cache/secondary-dexes/
\`\`\`

EOF

echo "[build-one] Publishing GitHub release ${RELEASE_TAG}.."
if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$OUTPUT_ROM" --clobber
  gh release edit "$RELEASE_TAG" --notes-file "$NOTES"
else
  gh release create "$RELEASE_TAG" "$OUTPUT_ROM" \
    --title "Koensayr ${RELEASE_TAG}" \
    --notes-file "$NOTES"
fi

echo "[build-one] Uploaded ${RELEASE_TAG}"
