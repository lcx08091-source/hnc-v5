# HNC hotfix19.1

## Theme

Start migrating runtime JSON writes to the unified `hnc_json` helper.

## Changes

- `json_set.sh top` now prefers `bin/hnc_json set-top` for top-level `rules.json` writes.
- The hotfix18 state-machine writer remains as a fallback when `hnc_json` is absent or fails.
- Value typing preserves the old behavior:
  - `true` / `false` => bool
  - `null` => null
  - strict numeric values => num
  - everything else => string
- Added regression coverage for commas, right braces, quotes, backslashes, Chinese text, bool, num, null and fallback behavior.

## Why

This is the first low-risk adoption step for the JSON unification track. It avoids a big-bang rewrite while making the most common top-level writes use one shared helper.
