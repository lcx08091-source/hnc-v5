# HNC hotfix22.1

## Purpose
Add a read-only v5.2 stats RC smoke gate after hotfix22.0's guarded RC control.

## Changes
- Add `bin/stats_v52_rc_smoke.sh`.
- Collect RC smoke output in JSON diagnostic bundles.
- Surface RC smoke status in JSON health panel.
- Include RC smoke in stats health summary.
- Add CI/preflight presence and executable checks.
- Add unit test skeleton for RC smoke states.

## Safety
- Does not enable or disable v5.2 RC.
- Does not switch WebUI default stats source.
- Does not modify legacy stats sampling or rollup.
- Does not touch TC / iptables / watchdog / JSON write paths.
