# HNC v5.2.0-rc1.13

## Purpose

Fix the rc1.12 diagnostic timeout wrapper regression on Android/Termux/SukiSU environments.

On the real device, helper scripts such as `stats_v52_web_status.sh`, `stats_v52_device_check.sh`, and `stats_v52_rc1_switch.sh` execute correctly when called directly. However, the rc1.12 report wrappers still classified them as `timeout`, and `gray_report` / `review_bundle` could be terminated by the wrapper.

This patch removes the fragile background watchdog wrapper from the v5.2 gray-report chain. The reports now execute helper scripts directly through `sh helper.sh`, classify missing/empty output separately, and avoid self-terminating the parent report shell.

## Changes

- Simplify helper execution in:
  - `bin/stats_v52_install_selfcheck.sh`
  - `bin/stats_v52_gray_report.sh`
  - `bin/stats_v52_review_bundle.sh`
- Stop using background watchdog/kill logic inside report aggregators.
- Treat readable helper scripts as present and execute them via `sh`.
- Preserve existing status semantics: missing, empty, unknown, warn, fail.
- Keep legacy stats as default and keep v5.2 RC disabled by default.
- Bump module version to `v5.2.0-rc1.13` / `520023`.

## Not changed

- No tc / iptables / watchdog / bandwidth / delay / blacklist / whitelist core changes.
- Does not enable v5.2 stats RC.
- Does not switch default stats source.
