# HNC hotfix21.7

## Goal

Small-scope opt-in control for the shadow stats migration path.

## Changes

- Add `bin/stats_shadow_control.sh`.
- Allow shadow stats to be enabled by a runtime flag:
  - `sh bin/stats_shadow_control.sh enable`
  - `sh bin/stats_shadow_control.sh disable`
- `stats_sample.sh` continues to write legacy stats as the source of truth.
- Shadow stats runs only when explicitly enabled by env, config, or runtime flag.
- JSON debug bundle and JSON health panel now expose shadow control status.
- `stats_health_summary.sh` includes the shadow control helper in component status.
- Add unit coverage for the shadow control helper.

## Safety

- No TC / iptables / watchdog logic changed.
- No legacy stats replacement.
- No rollup switch-over.
- No mandatory C helper writes.
