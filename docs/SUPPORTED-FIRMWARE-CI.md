# CI firmware builds

GitHub Actions workflow [`build-firmware-releases.yml`](../.github/workflows/build-firmware-releases.yml) produces patched **`rom.zip`** releases on [ryan-specter/koensayr-auto](https://github.com/ryan-specter/koensayr-auto/releases).

## Upstream sources

| Repository | Asset filter | Example release tags |
|------------|--------------|----------------------|
| [y1-community/y1-stock-rom](https://github.com/y1-community/y1-stock-rom) | `rom.zip` only | `Latest-3.0.7`, `3.0.2`, `2.8.2`, `ADB-2.1.9` |
| [rockbox-y1/rockbox](https://github.com/rockbox-y1/rockbox) | `rom.zip` only | `stable-v0.5`, recent `nightly-*` tags |

**Not built:** `rom_type_b.zip`, `rom_240p.zip`, `update.zip`, voice packs, and other non-`rom.zip` assets.

## Output naming

- **GitHub release tag:** `{slug}@{upstream-tag}` (e.g. `y1-stock-rom@3.0.2`, `rockbox@stable-v0.5`)
- **Internal firmware slug** (`--firmware-slug`): `@` replaced with `-` (e.g. `y1-stock-rom-3.0.2`) for `system-*-devel.img` naming

## Patch set

Every green CI build runs `./apply.bash --all --no-flash --accept-any-firmware`:

- Music-player UX (`--music-apk`)
- Bluetooth pairing (`--bluetooth`)
- ADB + bloat removal (`--adb`, `--remove-apps`)
- Root (`--root`)
- AVRCP 1.3 + Y1Bridge (`--avrcp`)

Diagnostic tooling under `tools/` is **not** embedded in the ROM.

## Expectations by upstream

| Input | CI expectation |
|-------|----------------|
| y1-stock-rom **3.0.2** / **3.0.7** | Highest confidence; matches [`KNOWN_FIRMWARES`](../apply.bash) |
| y1-stock-rom **2.8.2** / **ADB-2.1.9** | Attempted with `--skip-md5`; may fail until patch offsets are verified |
| rockbox **rom.zip** | Best-effort; custom `system.img` / BT stack may differ from stock |

Failed matrix jobs do not block other releases (`fail-fast: false`).

## Idempotency

A build is skipped when a release already exists and its notes contain the upstream asset SHA256, unless `workflow_dispatch` sets **force**.

## Scripts

| Script | Role |
|--------|------|
| [`tools/ci/discover-inputs.sh`](../tools/ci/discover-inputs.sh) | Emit JSON matrix of upstream `rom.zip` assets |
| [`tools/ci/build-one.sh`](../tools/ci/build-one.sh) | Download → patch → repack → `gh release` |
| [`tools/ci/extract-rom.sh`](../tools/ci/extract-rom.sh) | Unzip upstream ROM; record sparse `system.img` |
| [`tools/ci/repack-rom.sh`](../tools/ci/repack-rom.sh) | Replace `system.img` and zip patched `rom.zip` |
