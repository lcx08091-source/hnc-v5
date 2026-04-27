# HNC v5.1.0-rc1 hotfix18.8

Quality gate hotfix: CI preflight, JSON regression smoke tests, and version consistency checks.

## Added

- `bin/ci_preflight.sh`
  - rejects `.rej` / `.orig` patch residue
  - warns/fails on accidental secrets such as `.ssh` or private keys
  - checks key files and executable bits
  - optionally inspects built ZIP artifacts
  - runs JSON regression smoke tests when available

- `bin/json_regression_test.sh`
  - exercises JSON writers with commas, braces, quotes, backslashes, and Unicode strings
  - verifies resulting JSON remains valid after writes

- `bin/version_consistency_check.sh`
  - checks module.prop version/versionCode
  - fails on obvious old `hnc_httpd hotfix4` runtime strings
  - warns about stale WebUI version strings outside changelog contexts

- `.github/workflows/hnc-preflight.yml`
  - runs the preflight checks on push / PR / manual dispatch

## Notes

This hotfix does not change runtime QoS behavior. It prevents bad packages and stale-version regressions from reaching a flashable ZIP.
