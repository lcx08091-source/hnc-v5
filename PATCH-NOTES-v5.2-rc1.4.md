# HNC v5.2.0-rc1.4

Scope: scrubbed v5.2 stats gray-review bundle export.

This is a read-only gray-release support patch. It does not enable v5.2 stats, change the default stats source, or touch tc/iptables/watchdog/limit/delay logic.

## Added

- `bin/stats_v52_review_bundle.sh`
  - Exports a redacted review report for Claude/Gemini/GPT cross-checking.
  - Supports `text`, `json`, `markdown`, `bundle`, and `path` modes.
  - Redacts common sensitive/device identifiers from exported helper outputs:
    - IPv4 addresses
    - MAC addresses
    - email addresses
    - token/secret/password/auth JSON fields
  - Generates:
    - `/data/local/hnc/run/stats_v52_review_bundle.json`
    - `/data/local/hnc/run/stats_v52_review_bundle.txt`
    - `/data/local/hnc/run/stats_v52_review_bundle.md`
    - optional `/sdcard/Download/hnc-v52-rc1.4-review-*/` bundle

## Integrated

- `bin/json_diag_bundle.sh`
  - Collects review-bundle text/json/markdown outputs.
- `bin/json_health_panel.sh`
  - Surfaces review-bundle status in JSON health diagnostics.
- `bin/ci_preflight.sh`
  - Checks helper presence, executable bit, and redaction/review markers.

## Tests

- `test/unit/test_stats_v52_review_bundle.sh`
- `test/unit/test_json_health_panel_v52_rc1_4.sh`

## Version

- `version=v5.2.0-rc1.4`
- `versionCode=520014`
