# HNC v5.1.0-rc1 hotfix20.4

## Goal

Add a safer observation layer for legacy JSON fallback usage before any legacy
paths are removed. This release does not change runtime JSON write semantics.

## Changes

- Add `bin/json_legacy_fallback_status.sh` for read-only inspection of fallback telemetry.
- Support `status`, `json`, and `reset` commands.
- Include fallback telemetry in `json_diag_bundle.sh`.
- Expose fallback telemetry in `json_health_panel.sh` JSON output.
- Keep all legacy fallback paths intact.

## Runtime files

- `/data/local/hnc/run/json_legacy_fallback.log`
- `/data/local/hnc/run/json_legacy_fallback.count`

## Version

- `version=v5.1.0-rc1-hotfix20.4`
- `versionCode=509204`
