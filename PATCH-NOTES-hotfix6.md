# HNC v5.1.0-rc1 hotfix6

Focus: fix UI freeze / remote apply failure after rate-limit, rules.json corruption, stale mark restore, delay-only/offload sync, and local/remote state consistency.

## Fixed

1. `bin/json_set_batch.sh`
   - Use the same lock as `json_set.sh`: `$HNC/run/json.lock`.
   - Replace unsafe JSON number detection. IP addresses such as `192.168.118.112` are now quoted correctly.
   - Replace `sleep 0.05` with `_short_sleep()` for Android busybox ash compatibility.

2. `bin/tc_manager.sh`
   - `set_limit` now uses the robust `install_ingress_mirred()` path for uplink instead of the strict shell-only ingress helper.
   - If downlink succeeds but uplink/IFB fails, return rc `8` as partial success so callers can keep downlink active and persist `up_mbps=0` instead of failing the whole UI action.
   - `set_delay` now prepares IFB + ingress mirred for delay-only rules.
   - `restore_rules` no longer restores inactive `mark_id`-only devices. It restores only when there is an actual positive limit or delay/loss/jitter rule.
   - `restore_rules` can parse quoted kbit values as well as numeric Mbps values.

3. `bin/apply_device_rule.sh`
   - Captures `tc_manager.sh set_limit` rc/output.
   - Handles rc `8` partial uplink failure by keeping the downlink rule and persisting `up_mbps=0`.
   - JSON partial write failures now return non-zero instead of reporting fake success.
   - `bl_del` uses rules.json IP fallback when the device is offline, removing stale IP DROP rules.

4. `daemon/hnc_httpd/action.go`
   - Fix duplicate `frac :=` compile error in `rateToMbpsStr`.
   - Surface partial uplink failure as a success warning.

5. `daemon/hnc_httpd/action_v5.go`
   - delay-only set now notifies offload scheduler with `OFFLOAD_NOTIFY_LIMIT <mac> 1`.
   - delay clear notifies offload clear when no limit remains.
   - delay set failure after new mid allocation now rolls back iptables mark and mark_id.
   - delay-only clear removes tc/iptables state instead of leaving mark/class residue.
   - JSON partial write on delay set/clear now returns an error instead of fake success.

6. `webroot/index.html`
   - Fix batch template failure toast referencing undefined `results.length`.

7. `bin/json_set.sh`
   - Replace bash-only brace expansion in `init_dirs` with busybox ash-compatible mkdir arguments.

## Rebuild required

Shell/WebUI changes apply directly after install. Go changes require rebuilding:

```sh
cd daemon/hnc_httpd && sh build.sh && cd ../..
```

If your CI packages prebuilt binaries, make sure the new `daemon/hnc_httpd/hnc_httpd` is included.

## Notes

This hotfix intentionally avoids introducing a background tc/iptables queue. It keeps write operations sequential and focuses on correctness and state convergence.
