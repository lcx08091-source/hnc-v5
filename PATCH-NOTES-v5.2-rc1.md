# HNC v5.2.0-rc1

Scope: staged v5.2 stats gray release.

This release does **not** make the new v5.2/shadow statistics pipeline the default. Legacy stats remains the default source. The release only adds a guarded gray switch so real devices can enter a controlled v5.2 RC monitoring state after the hotfix22.x readiness, smoke and device-check gates pass.

## Added

- `bin/stats_v52_rc1_switch.sh`
  - `status|json|text`: reports v5.2-rc1 gray state.
  - `enable`: runs the existing guarded `stats_v52_rc_control.sh enable`, then enables shadow stats sampling.
  - `disable|rollback`: disables shadow stats sampling, disables the RC flag, and removes the v5.2-rc1 marker.
- `json_diag_bundle.sh` collection for v5.2-rc1 switch JSON/TXT and marker flag.
- `json_health_panel.sh` exposure for v5.2-rc1 switch state.
- CI preflight required/executable checks for the new helper.
- Unit test coverage for enable/rollback and blocked gate behavior.

## Safety guarantees

- Legacy stats remains default.
- The new switch does not touch `tc`, `iptables`, `watchdog`, HTB, netem, IFB or offload logic.
- Enabling v5.2-rc1 still depends on the existing hotfix22.5 RC/device-check gates.
- Rollback is one command: `sh /data/local/hnc/bin/stats_v52_rc1_switch.sh rollback`.

## Version

- `version=v5.2.0-rc1`
- `versionCode=520001`
