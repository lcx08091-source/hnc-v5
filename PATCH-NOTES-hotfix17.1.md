# HNC v5.1.0-rc1 hotfix17.1

Safe capability recovery after hotfix16.9.

Root probe on Xiaomi Mi 10 / MIUI14 showed `/system/bin/tc` is iproute2, dummy supports HTB/netem, and IFB/mirred/police are unavailable. Therefore downlink HTB and egress-only netem should be recoverable, while uplink remains unsupported.

Changes:
- Add `bin/capability_probe.sh` to generate `/data/local/hnc/run/capabilities.json` at boot.
- Preserve ROM `qdisc mq root` on Wi-Fi AP interface.
- Try MQ child HTB before any root replacement.
- Try `parent 0:1` / `parent :1` and `replace` / `add` for legacy Android tc compatibility.
- Do not delete mq root during retry.
