# HNC v5.3.0-rc20.0

## Scope

RC20 combines the small RC19.1 stability fix with the next DPI L3 read-only label layer.

## Changes

- hnc_dpid upgraded to `0.3.0-l3-rc20`.
- Added recoverable AF_PACKET rebind/retry when hotspot interface temporarily returns `network is down` / ENETDOWN.
- Added read-only L3 app/category labels derived from DNS/SNI suffix rules.
- Added per-client `top_apps` and `top_categories` in `dpi_state.json`.
- Added global `top_apps`, `top_categories`, `l3_enabled`, and `l3_rule_version` fields.
- WebUI DPI page now shows L2/L3 client attribution chips.
- Artifact/preflight gates accept the rc20 dpid marker.

## Safety boundaries

- No NFQUEUE.
- No DNS hijacking.
- No QUIC parsing.
- No tc/iptables mark changes.
- No automatic throttling or policy enforcement.
- No offload modification.

RC20 labels are hints from metadata only. They do not represent precise App identification and are not used for enforcement.
