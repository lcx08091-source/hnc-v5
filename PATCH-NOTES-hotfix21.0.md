# HNC hotfix21.0

Stats diagnostics baseline before the v5.2 stats overhaul.

## Changes

- Add `bin/stats_diag.sh` read-only diagnostics for `stats_raw.jsonl` and `stats_daily.jsonl`.
- Include stats diagnostics in JSON diagnostic bundles without copying full raw/daily files by default.
- Expose stats diagnostics in the JSON health panel payload.
- Add Termux-safe regression coverage for stats diagnostics.
- Bump version to `v5.1.0-rc1-hotfix21.0` / `509210`.

## Notes

This hotfix does not change stats sampling, rollup, TC, iptables, JSON writes, watchdog, or WebUI behavior. It is a safe observation step before the larger v5.2 stats rebuild.
