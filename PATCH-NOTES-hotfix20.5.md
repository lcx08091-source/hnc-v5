# HNC hotfix20.5

Goal: cautiously test optional C hnc_json write coverage on the non-critical `device_names.json` path.

Changes:
- Extended `daemon/hotspotd/tools/hnc_json.c` with guarded `set-object-key` / `del-object-key` support for flat JSON objects.
- `bin/hnc_json` now tries the optional C helper for `set-object-key` / `del-object-key` first and falls back to the existing shell implementation on any failure.
- Runtime callers such as `json_set.sh name_set/name_del` continue to call `bin/hnc_json`, so the migration stays centralized and reversible.
- Added regression coverage for the C object-key write bridge.

Version: `v5.1.0-rc1-hotfix20.5` / `509205`.
