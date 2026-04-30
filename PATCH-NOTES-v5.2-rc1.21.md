# HNC v5.2.0-rc1.21

## Target

Fix gray observation traffic classification when raw/daily counters are already positive but large enough to overflow shell arithmetic on some Android environments.

## Changes

- `bin/stats_v52_gray_observe.sh` no longer computes traffic by adding raw/daily rx/tx counters in shell arithmetic.
- It now checks each counter independently and reports `traffic_state=traffic_seen` if any raw or daily counter is positive.
- It normalizes stale `shadow_quality=observed_zero_traffic` to `shadow_quality=observed` when positive traffic is present.
- `test/unit/test_stats_v52_gray_observe.sh` keeps a large-total regression case based on rc1.20 real-device output.

## Safety

- Does not enable v5.2 RC.
- Does not switch the default stats source.
- Does not touch tc, iptables rule application, watchdog, limit, delay, blacklist, or whitelist paths.
- Legacy stats remains the default source.
