# HNC hotfix21.6

Stats health summary for WebUI diagnostics.

- Adds `bin/stats_health_summary.sh` as a read-only summary layer for staged v5.2 stats migration.
- Aggregates existing stats diagnostics: baseline, identity, retention, shadow, and compare.
- Writes `/data/local/hnc/run/stats_health_summary.json` and `.txt` for JSON health/debug bundle consumption.
- Integrates the summary into `json_health_panel.sh` and `json_diag_bundle.sh`.
- Adds CI/preflight helper presence checks and a unit test.
- Does not switch WebUI to shadow stats.
- Does not change stats sampling, rollup, TC, iptables, watchdog, or JSON write paths.

Version: `v5.1.0-rc1-hotfix21.6` / `509216`.
