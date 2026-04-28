# HNC v5.1.0-rc1 hotfix22.2

Scope: v5.2 stats RC gate hardening only. This patch does not touch tc, iptables, watchdog, speed limit, latency, whitelist, blacklist, or hotspot control paths.

## Fixed

- Fixed `bin/stats_v52_rc_smoke.sh` JSON escaping. The hotfix22.1 helper accidentally emitted empty string fields for status, recommendation, component status, and output paths.
- Reworked `stats_v52_rc_smoke.sh` status/bool extraction to avoid fragile `head` pipelines in tiny Android shells.
- Fixed `bin/stats_health_summary.sh` newline/tab/carriage-return escaping so summary JSON remains parseable and non-empty.
- Updated `bin/ci_preflight.sh` banner to hotfix22.2.

## Tests

- Strengthened `test/unit/test_stats_v52_rc_smoke.sh` to verify fail/disabled/pass/fail transitions and reject empty critical JSON fields.
- Strengthened `test/unit/test_stats_health_summary.sh` to cover disabled/warn, pass/ok, and fail states while rejecting empty status/recommendation fields.

## Version

Recommended module version bump when applying to the full repo:

- `version=v5.1.0-rc1-hotfix22.2`
- `versionCode=509222`
