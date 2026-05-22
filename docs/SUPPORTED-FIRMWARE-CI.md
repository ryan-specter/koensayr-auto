# CI firmware builds

GitHub Actions workflow [`build-firmware-releases.yml`](../.github/workflows/build-firmware-releases.yml) produces patched **`rom.zip`** releases on [ryan-specter/koensayr-auto](https://github.com/ryan-specter/koensayr-auto/releases).

## Upstream sources (allowlist)

CI only builds these upstream tags (see [`tools/ci/discover-inputs.sh`](../tools/ci/discover-inputs.sh)):

| Repository | Upstream tags | Asset |
|------------|---------------|-------|
| [y1-community/y1-stock-rom](https://github.com/y1-community/y1-stock-rom) | **3.0.2**, **Latest-3.0.7** | `rom.zip` |

**Koensayr release names:** stock **3.0.7** firmware is published as `y1-stock-rom@3.0.7` even though the upstream tag is `Latest-3.0.7`. Release notes still record the upstream tag.

**Not built by CI:** other stock tags (`2.8.2`, `ADB-2.1.9`, `type-b-1.7.6`, …), `rom_type_b.zip`, `rom_240p.zip`, `update.zip`, voice packs, and other assets.

Rockbox-Y1 `rom.zip` is out of scope: the image has no Innioasis `com.innioasis.y1` music APK, so the stock patch pipeline does not apply. Build Rockbox releases manually if needed.

To add another stock tag, extend `Y1_UPSTREAM_TAGS` in `discover-inputs.sh`.

## Output naming

- **GitHub release tag:** `{slug}@{firmware-version}` (e.g. `y1-stock-rom@3.0.2`, `y1-stock-rom@3.0.7`)
- **Internal firmware slug** (`--firmware-slug`): `@` replaced with `-` (e.g. `y1-stock-rom-3.0.2`) for `system-*-devel.img` naming

## Patch set

Every green CI build verifies upstream `rom.zip` SHA256 and MD5 against [`KNOWN_FIRMWARES`](../apply.bash), then runs `./apply.bash --all --no-flash` (strict manifest match — no `--accept-any-firmware`):

- Music-player UX (`--music-apk`)
- Bluetooth pairing (`--bluetooth`)
- ADB + bloat removal (`--adb`, `--remove-apps`)
- Root (`--root`)
- AVRCP 1.3 + Y1Bridge (`--avrcp`)

Diagnostic tooling under `tools/` is **not** embedded in the ROM.

## Expectations by upstream

| Input | CI expectation |
|-------|----------------|
| y1-stock-rom **3.0.2** / **3.0.7** | Supported; matches [`KNOWN_FIRMWARES`](../apply.bash) (3.0.7 accepts both Innioasis and y1-community `system.img` layouts) |

Failed matrix jobs do not block other releases (`fail-fast: false`).

## Idempotency

- **Push to `main`:** always rebuilds and republishes (`--force`), so patched `com.innioasis.y1` APKs and other `--all` changes land in the latest `rom.zip` releases. Each publish **deletes** the prior GitHub release tag and recreates it (no leftover assets such as older `rom-koensayr.zip` names).
- **Weekly schedule:** skips a matrix entry only when `build-manifest.json` on the existing release matches both the upstream `rom.zip` SHA256 and the current koensayr git revision (`koensayr_git_sha`).
- **`workflow_dispatch`:** set **force** to rebuild regardless.

## Scripts

| Script | Role |
|--------|------|
| [`tools/ci/discover-inputs.sh`](../tools/ci/discover-inputs.sh) | Emit JSON matrix for allowlisted upstream `rom.zip` assets |
| [`tools/ci/build-one.sh`](../tools/ci/build-one.sh) | Download → MD5/SHA256 gate → patch → repack → `gh release` |
| [`tools/ci/firmware-manifest.sh`](../tools/ci/firmware-manifest.sh) | Read `KNOWN_FIRMWARES` rows from `apply.bash` |
| [`tools/ci/patch-revision.sh`](../tools/ci/patch-revision.sh) | Current git SHA recorded in `build-manifest.json` |
| [`.github/workflows/workflow.md`](../.github/workflows/workflow.md) | User-facing intro prepended to each GitHub release (edit for new features) |
| [`tools/ci/extract-rom.sh`](../tools/ci/extract-rom.sh) | Unzip upstream ROM; record sparse `system.img` |
| [`tools/ci/repack-rom.sh`](../tools/ci/repack-rom.sh) | Replace `system.img` and zip patched `rom.zip` |
