# HNC hotfix21.4 patch notes

## Scope

Add the shadow stats cross-day rollup layer for the v5.2 stats migration.

This is still a safe transition hotfix:
- legacy stats remain unchanged
- shadow stats remain optional
- WebUI does not switch to shadow stats
- no changes to TC / iptables / watchdog
- no changes to JSON write paths

## Changes

- Add `bin/stats_shadow_rollup.sh`
  - rolls `stats_shadow_raw.jsonl` into `stats_shadow_daily.jsonl`
  - uses MAC/device_id as long-term identity
  - uses previous-day baseline when available
  - falls back to first sample of target day
  - clamps counter resets instead of writing negative deltas
  - replaces existing rows for the target date to keep rollup idempotent
- Update `bin/stats_shadow_sample.sh`
  - adds `date` into shadow raw rows
  - maintains `run/stats_shadow_last_date`
  - triggers shadow rollup when date changes
- Update `bin/stats_shadow_diag.sh`
  - reports raw + daily shadow stats health
  - reports legacy no-date shadow rows from hotfix21.3
  - reports daily invalid lines, unique dates/devices, last rolled date
- Update JSON debug bundle and health panel to include shadow daily diagnostics.
- Update `ci_preflight.sh` required helper checks.
- Add tests:
  - `test/unit/test_stats_shadow.sh`
  - `test/unit/test_stats_shadow_rollup.sh`

## Version

- version: `v5.1.0-rc1-hotfix21.4`
- versionCode: `509214`

## Commit message

```sh
git commit -m "hotfix21.4: add shadow stats cross-day rollup"
```
