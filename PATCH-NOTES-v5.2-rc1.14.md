# HNC v5.2.0-rc1.14

## Purpose

Speed up v5.2 gray-report/review-bundle generation on Android/Termux while keeping the v5.2 stats RC disabled by default.

## Changes

- `stats_v52_gray_report.sh`
  - Reuses cached helper outputs by default.
  - Avoids re-running the same expensive helper tree for raw markdown sections.
  - Adds `fast_cache`, `refresh`, and `full_raw` fields to report output.
  - Supports forced refresh with `HNC_V52_REPORT_REFRESH=1`.
  - Supports full raw re-collection with `HNC_V52_REPORT_FULL=1`.
- `stats_v52_review_bundle.sh`
  - Consumes `stats_v52_gray_report` cache instead of re-running all helpers.
  - Copies cached run artifacts into bundle mode.
- `stats_v52_install_selfcheck.sh`
  - Version label updated to rc1.14.
- `module.prop`
  - Bumped to `v5.2.0-rc1.14` / `520024`.

## Safety

- Does not enable v5.2 RC.
- Does not switch stats source.
- Does not touch tc / iptables / watchdog / limit / delay logic.
- Legacy stats remains the default source.
