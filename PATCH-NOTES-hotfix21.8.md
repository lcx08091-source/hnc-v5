# HNC hotfix21.8

## Goal

Add an opt-in WebUI/API bridge for reading shadow stats without replacing the legacy stats pipeline.

## Changes

- `/api/stats` now accepts `source=legacy|shadow`.
- KSU WebUI stats page adds a compact stats source selector.
- Default remains legacy stats. The selector preference is stored only in WebView localStorage.
- Add `bin/stats_source_diag.sh` to report legacy/shadow file availability and API source support.
- JSON diagnostic bundle and JSON health panel include stats source diagnostics.
- CI preflight checks the new helper and unit test coverage.

## Safety

- Legacy stats remains the default and source of truth.
- Shadow source is read-only from WebUI/API and must be manually selected.
- No TC / iptables / watchdog logic changed.
- No stats sampling or rollup behavior changed.
