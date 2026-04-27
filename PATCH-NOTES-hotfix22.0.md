# HNC v5.1.0-rc1 hotfix22.0

## Theme

Guarded v5.2 stats RC control.

This hotfix does not switch the default stats system and does not modify legacy
stats sampling, TC, iptables, watchdog, or JSON write paths. It adds a small
runtime control helper that can only enable a v5.2 stats RC flag after the
migration readiness gate reports ready, unless an explicit force environment
variable is used for controlled testing.

## Changes

- Add `bin/stats_v52_rc_control.sh`.
- Integrate v5.2 RC control state into stats health summary.
- Collect v5.2 RC control status in JSON diagnostic bundles.
- Surface v5.2 RC control state in JSON health panel output.
- Add CI/preflight presence and executable checks.
- Add `test/unit/test_stats_v52_rc_control.sh`.

## Version

- version: `v5.1.0-rc1-hotfix22.0`
- versionCode: `509220`

## Safety

- Default state is disabled.
- `enable` refuses to proceed unless `stats_migration_readiness.sh` reports
  `ready=true`.
- `disable` only removes the RC flag.
- No stats data files are rewritten.
- No TC / iptables / watchdog logic is changed.
