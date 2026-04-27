# HNC hotfix20.1

## Scope

Legacy JSON fallback telemetry only. This release intentionally does not remove
legacy JSON writers yet. It records when fallback paths are used so later cleanup
can be based on runtime evidence instead of guessing.

## Changes

- Add best-effort fallback logging to `bin/json_set.sh`.
- Add best-effort fallback logging to `bin/json_set_batch.sh`.
- Record fallback events in:
  - `/data/local/hnc/run/json_legacy_fallback.log`
  - `/data/local/hnc/run/json_legacy_fallback.count`
- Keep all existing legacy fallback behavior intact.
- Bump version to `v5.1.0-rc1-hotfix20.1` / `509201`.

## Notes

This is a measurement hotfix. Do not delete legacy paths until several builds show
that fallback is not being triggered in normal use.
