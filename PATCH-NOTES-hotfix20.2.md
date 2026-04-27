# HNC v5.1.0-rc1 hotfix20.2

## Scope

This release starts the cautious C migration for `hnc_json` without moving JSON writes out of the proven shell frontend.

## Changes

- Added an optional `bin/hnc_json_c` read-only helper integration path in `bin/hnc_json`.
- The shell frontend may delegate only these commands when `bin/hnc_json_c` exists and passes `version` probing:
  - `validate <file>`
  - `get-top <file> <key>`
  - `version`
- All write commands still use the shell implementation:
  - `set-top`
  - `set-device`
  - `set-device-batch`
  - `set-object-key` / `del-object-key`
  - blacklist / token helpers
- Expanded `daemon/hotspotd/tools/hnc_json.c` from a prototype into a conservative read-only helper.
- Updated `daemon/hotspotd/tools/build_hnc_json.sh` to build the helper into `bin/hnc_json_c` by default.
- Added regression coverage for:
  - shell fallback when the C helper is absent
  - optional C helper build when a compiler exists
  - read-only parity for `validate` and `get-top`

## Risk control

- No runtime JSON write path is moved to C in this release.
- If `bin/hnc_json_c` is absent, broken, or disabled with `HNC_JSON_C_DISABLE=1`, the shell frontend remains the fallback.
- The C helper is read-only, so it cannot corrupt live JSON files.
