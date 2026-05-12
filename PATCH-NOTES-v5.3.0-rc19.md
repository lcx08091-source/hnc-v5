# HNC v5.3.0-rc19.0 Patch Notes

## Scope

RC19 adds DPI L2 per-client DNS/SNI attribution on top of the rc18.1 fixed DPI packaging baseline.

This release remains read-only and passive:

- no NFQUEUE
- no DNS hijacking
- no QUIC parsing
- no app/category classification rules
- no tc/iptables mark changes
- no automatic limiting or prioritization
- no offload modification

## Added

- `hnc_dpid` version `0.2.0-l2-rc19`.
- `dpi_state.json` schema `1.1`.
- Per-client L2 metadata aggregation:
  - `clients.<client_ip>.client_ip`
  - `clients.<client_ip>.client_mac`
  - `clients.<client_ip>.dns_events`
  - `clients.<client_ip>.tls_events`
  - `clients.<client_ip>.top_hostnames`
  - `clients.<client_ip>.top_sni`
  - `clients.<client_ip>.first_seen`
  - `clients.<client_ip>.last_seen`
- Global L2 counters:
  - `client_count`
  - `top_hostnames`
  - `top_sni`
  - `unique_hostnames`
  - `unique_sni`
- WebUI DPI page section: “设备域名画像 / L2”.

## Changed

- `module.prop` bumped to `v5.3.0-rc19.0` / `versionCode=530020`.
- `artifact_sanity_check.sh` and `ci_preflight.sh` accept the `0.2.0-l2-rc19` dpid marker.
- `hnc_httpd` embedded version string updated to `v5.3.0-rc19.0` for artifact gate consistency.

## Safety

RC19 only records recent metadata counters and host/SNI names already visible to the hotspot gateway. It does not store payloads and does not change packet forwarding behavior.

Debug logs may still include full qname/SNI if `log_level=debug`; keep production/default config at `info`.
