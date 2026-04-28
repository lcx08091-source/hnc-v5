# HNC v5.2.0-rc1.11

## Purpose

Fix inconsistent installed diagnostic chain after v5.2-rc1.10. Some builds had the
WebUI bridge fixes but missed earlier v5.2 diagnostic helpers, causing:

- `stats_v52_web_status.sh` missing from `/data/local/hnc/bin`
- `json-health.html` missing `v52_web_status_raw` wiring
- `stats_v52_install_selfcheck.sh` still expecting rc1.3
- gray report/review bundle possibly hanging when a child helper stalls

## Changes

- Restore `bin/stats_v52_web_status.sh`.
- Restore `webroot/json-health.html` v5.2 RC status card wiring.
- Update `stats_v52_install_selfcheck.sh` for rc1.x dynamic version checks.
- Add hard helper timeouts to `stats_v52_gray_report.sh`.
- Add hard helper timeouts to `stats_v52_review_bundle.sh`.
- Bump module version to `v5.2.0-rc1.11` / `520021`.

## Safety

Read-only diagnostics only. No changes to tc, iptables, watchdog, speed limits,
latency, blacklist/whitelist, or stats RC enable logic.
