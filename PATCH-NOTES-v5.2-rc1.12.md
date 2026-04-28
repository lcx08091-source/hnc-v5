# HNC v5.2.0-rc1.12

## Purpose

Fix false `missing` / `timeout` diagnostics in the v5.2 gray-report chain.

The rc1.11 helper timeout wrapper polled child processes with `kill -0`. On Android shell this can keep succeeding for an unreaped exited child, so fast helpers may be misclassified as `missing or timeout` until the watchdog kills them. This caused `stats_v52_gray_report.sh` and `stats_v52_review_bundle.sh` to report missing helpers even when direct execution worked.

## Changes

- Replace `kill -0` polling timeout loops with a `wait + watchdog done-file` pattern in:
  - `bin/stats_v52_install_selfcheck.sh`
  - `bin/stats_v52_gray_report.sh`
  - `bin/stats_v52_review_bundle.sh`
- Distinguish missing helper, timeout helper, and empty helper output.
- Treat readable helper scripts as present even when callers execute them via `sh helper.sh`.
- Keep legacy stats as default and keep v5.2 RC disabled by default.
- Bump module version to `v5.2.0-rc1.12` / `520022`.

## Not changed

- No tc / iptables / watchdog / bandwidth / delay / blacklist / whitelist core changes.
- Does not enable v5.2 stats RC.
- Does not switch default stats source.
