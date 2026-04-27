# HNC hotfix20.6

Goal: expand the optional C hnc_json write experiment to blacklist and remote token revoke paths while keeping shell fallback.

Changes:
- Extended `daemon/hotspotd/tools/hnc_json.c` with guarded support for:
  - `add-array-unique`
  - `del-array-value`
  - `token-revoke`
  - `token-revoke-all`
- `bin/hnc_json` now tries the optional C helper for those commands first and falls back to the shell writer on failure.
- No legacy fallback is removed. The hotfix20.1/20.4 telemetry remains available for observation.
- Added regression coverage for the C blacklist/token write bridge.

Version: `v5.1.0-rc1-hotfix20.6` / `509206`.
