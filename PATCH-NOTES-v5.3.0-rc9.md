# HNC v5.3.0-rc9

Scope: rc7 audit P1 maintenance and consistency fixes, based on v5.3.0-rc8.

## Fixed

- watchdog uplink mirred detection now matches actual tc output using a case-insensitive `mirred.*ifb0` pattern.
- `device_detect.sh` shell ARP scan now only accepts entries from the detected hotspot interface, preventing upstream/non-hotspot ARP entries from appearing as hotspot clients.
- Remote access action wording changed from exact `~60s` to `约 1 分钟`.
- Added `bin/hnc_constants.sh` and routed duplicated `MARK_BASE` / HTTP ports through shared shell constants in iptables, IPv6 sync, and watchdog paths.

## Not included

- SQM async jobs are intentionally deferred until the smaller maintenance fixes stabilize.
- localStorage `hnc.transport_hint_reason.v1` remains a harmless orphan and is intentionally not part of this release.
