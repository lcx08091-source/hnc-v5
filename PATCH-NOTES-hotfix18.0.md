# HNC hotfix18.0 patch notes

## Goal

Start the JSON unification track with the highest-risk write paths first.

## Fixed

- `json_set.sh top` no longer uses `[^,}]*` to replace a top-level value.
- `json_set.sh device` no longer uses a flat regex to replace a per-device value.
- Values containing commas, right braces, escaped quotes, or backslashes are handled by a character-level JSON scanner.
- IP-like strings such as `192.168.43.5` remain quoted and no longer risk bare-number JSON corruption.

## Scope

This hotfix intentionally limits the first JSON rewrite to:

- `top`
- `device`

Other JSON helpers such as blacklist/name/template parsing are left unchanged for hotfix18.x to reduce risk.

## Tests added

- top string with comma
- top string with right brace
- device string with comma/right brace
- device IP-like string quoting
- device old value with escaped quote

## Version

- `version=v5.1.0-rc1-hotfix18.0`
- `versionCode=509180`
