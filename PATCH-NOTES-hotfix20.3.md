# HNC v5.1.0-rc1 hotfix20.3

## Theme

Termux / CI preflight cleanup after the JSON helper migration.

## Changes

- Make `bin/ci_preflight.sh` version checks dynamic instead of hard-coded to hotfix18.8.
- Make `bin/version_consistency_check.sh` validate version format/code instead of warning about hotfix18.8.
- Move JSON regression temporary output away from hard-coded `/tmp` so Termux environments without writable `/tmp` do not fail spuriously.
- Keep all runtime JSON writer behavior unchanged.

## Version

- `version=v5.1.0-rc1-hotfix20.3`
- `versionCode=509203`
