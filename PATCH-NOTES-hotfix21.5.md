# HNC v5.1.0-rc1 hotfix21.5

## Scope

Add read-only old-vs-shadow stats comparison diagnostics before the v5.2 stats migration.

## Changes

- Add `bin/stats_compare.sh`.
- Compare legacy `stats_daily.jsonl` with shadow `stats_shadow_daily.jsonl` by `date + mac`.
- Generate:
  - `/data/local/hnc/run/stats_compare.json`
  - `/data/local/hnc/run/stats_compare.txt`
- Include compare output in `json_diag_bundle.sh`.
- Expose compare status in `json_health_panel.sh`.
- Add preflight/test coverage for the new helper.

## Safety

- Read-only against legacy and shadow stats files.
- Does not replace WebUI stats.
- Does not change sampling, rollup, JSON write, TC, iptables, watchdog, or offload logic.
