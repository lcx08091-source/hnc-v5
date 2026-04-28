# HNC v5.2.0-rc1.2

Scope: install/first-boot safety self-check for the staged v5.2 stats gray release.

This patch remains read-only for network control paths. It does not touch tc,
iptables, watchdog, speed limits, latency injection, blacklist/whitelist rules, or
stats source switching.

## Added

- `bin/stats_v52_install_selfcheck.sh`
  - Verifies v5.2 RC gray helper presence.
  - Verifies JSON health page wiring.
  - Verifies rollback path is present.
  - Verifies legacy stats remains the default source.
  - Emits `/data/local/hnc/run/stats_v52_install_selfcheck.json` and `.txt`.

## Integrated

- `bin/json_diag_bundle.sh` now collects install self-check JSON/TXT output.
- `bin/json_health_panel.sh` exposes install self-check raw status.
- `bin/ci_preflight.sh` checks the self-check helper and basic guard strings.

## Tests

- `test/unit/test_stats_v52_install_selfcheck.sh`
- `test/unit/test_json_health_panel_v52_rc1_2.sh`

Version: `v5.2.0-rc1.2`
VersionCode: `520012`
