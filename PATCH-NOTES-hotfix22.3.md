# HNC v5.1.0-rc1 hotfix22.3

Scope: v5.2 stats diagnostics closure only. This patch does not touch tc, iptables, watchdog, speed limit, latency, whitelist, blacklist, hotspot control, or JSON write paths.

## Added

- Added `bin/stats_v52_diag_bundle.sh`, a read-only v5.2 stats diagnostic aggregator.
- The aggregator collects normalized status from:
  - `stats_health_summary.sh`
  - `stats_v52_rc_control.sh`
  - `stats_v52_rc_smoke.sh`
  - `stats_migration_readiness.sh`
  - `stats_compare.sh`
  - `stats_source_diag.sh`
  - `stats_shadow_diag.sh`
  - `stats_shadow_control.sh`
  - `stats_diag.sh`
  - `stats_identity_diag.sh`
  - `stats_retention_diag.sh`
- Writes:
  - `/data/local/hnc/run/stats_v52_diag_bundle.json`
  - `/data/local/hnc/run/stats_v52_diag_bundle.txt`

## Changed

- `bin/json_diag_bundle.sh` now runs and copies the v5.2 diagnostic bundle output.
- `bin/json_health_panel.sh` now exposes `has_v52_diag_bundle_helper` and `v52_diag_bundle_raw`.
- `bin/ci_preflight.sh` now checks the v5.2 diagnostic aggregator helper.
- `module.prop` version is bumped to hotfix22.3.

## Tests

- Added static regression checks for the new stats diagnostic bundle helper and its JSON health/diagnostic bundle integration.

## Version

- `version=v5.1.0-rc1-hotfix22.3`
- `versionCode=509223`
