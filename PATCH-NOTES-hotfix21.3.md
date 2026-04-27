# HNC hotfix21.3

Scope: stats shadow write framework for the later v5.2 stats migration.

Changes:
- Added `bin/stats_shadow_sample.sh`.
  - Writes optional shadow samples to `data/stats_shadow_raw.jsonl`.
  - Uses stable `device_id="mac:<mac>"` while preserving current IPs as auxiliary metadata.
  - Does not replace `stats_raw.jsonl` or `stats_daily.jsonl`.
- Added `bin/stats_shadow_diag.sh`.
  - Reports shadow enabled state, shadow raw size, invalid lines, unique devices and last sample time.
- `stats_sample.sh` can invoke shadow sampling only when explicitly enabled by:
  - `HNC_STATS_SHADOW_ENABLE=1`, or
  - `data/config.json` containing `"stats_shadow_enabled":true`.
- JSON diagnostic bundle now includes shadow stats diagnostics and shadow raw tail.
- JSON health panel now exposes shadow stats status.
- CI preflight now checks the new shadow helper scripts.

Safety:
- Shadow stats are opt-in by default.
- Existing stats sampling, rollup, WebUI stats display, TC, iptables, watchdog and JSON write paths are unchanged.
- This is not the final v5.2 switch; it only lays down the side-channel framework.

Version:
- `v5.1.0-rc1-hotfix21.3`
- `versionCode=509213`
