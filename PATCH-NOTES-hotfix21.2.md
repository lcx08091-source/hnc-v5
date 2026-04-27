# HNC hotfix21.2

Stats retention/config diagnostics before the v5.2 stats overhaul.

## Added

- `bin/stats_retention_diag.sh`
  - Read-only diagnostics for stats retention settings.
  - Checks `stats_raw.jsonl` / `stats_daily.jsonl` sizes and line counts.
  - Reports lines older than the configured retention window.
  - Reports invalid sampled lines in the scanned tail window.
  - Reports `stats_rollup.sh` retention defaults.
- `test/unit/test_stats_retention_diag.sh`

## Integrated

- `bin/json_diag_bundle.sh` now collects retention diagnostics.
- `bin/json_health_panel.sh` now exposes retention diagnostics under `stats.retention_raw`.
- `bin/ci_preflight.sh` checks that the new helper exists and is executable.

## Safety

- Does not modify stats sampling logic.
- Does not modify rollup logic.
- Does not modify JSON write paths.
- Does not touch tc / iptables / watchdog runtime behavior.

Version: `v5.1.0-rc1-hotfix21.2`
VersionCode: `509212`
