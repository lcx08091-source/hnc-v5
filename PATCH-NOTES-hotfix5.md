# HNC v5.1.0-rc1 hotfix5

Scope: remote access/state consistency, on-device KSU WebUI batching, and limit/tc edge cases.

## Fixes

1. Remote dashboard rate conversion precision
   - `daemon/hnc_httpd/web/app.js` no longer converts kbit to mbit using 1024 and `Math.round()`.
   - It now keeps exact kbit values unless the value is an exact multiple of 1000 kbit.
   - This prevents inputs such as 0.2 MB/s (1600 kbit) from being sent as 2 mbit.

2. `/api/devices` startup/offline consistency
   - `daemon/hnc_httpd/server.go` treats a missing/temporarily unreadable `devices.json` as an empty live snapshot instead of returning HTTP 503.
   - Persistent rule-only and blacklist-only devices can still be shown and cleared when hotspotd is starting or hotspot is off.
   - `apiDevices` now builds the snapshot under `stateMu.RLock()` but releases the lock before writing the HTTP response, so slow remote clients do not block write actions.
   - Rule/name overlay now tolerates MAC case differences.

3. Downlink-only limits no longer depend on IFB
   - `bin/tc_manager.sh set_limit` no longer initializes IFB/mirred when only downlink shaping is requested.
   - IFB is still required and checked when uplink shaping is requested.
   - When up=0, existing IFB class clearing is best-effort and will not fail a downlink-only rule.

4. Roll back packet marking if tc setup fails
   - `bin/apply_device_rule.sh limit` now removes the iptables mark if `tc_manager.sh set_limit` fails after marking.
   - This avoids leaving traffic classified into a failed/partial tc setup while `rules.json` was not updated.

5. On-device KSU batch operations are sequential
   - `webroot/index.html` batch clear/apply/block/unblock operations now run device writes sequentially.
   - This avoids launching many `ksu.exec curl` commands that just queue behind the Go write lock and time out, which previously could make local data look out of sync.

## Verification performed in patch environment

- `sh -n` over shell scripts passed.
- `node --check daemon/hnc_httpd/web/app.js` passed.
- Inline scripts extracted from `webroot/index.html` passed `node --check`.
- `gofmt` was run on modified Go files.
- Full `go test` could not run here because the environment has Go 1.23.2 while this project requires Go >= 1.25.0.

## Build note

Rebuild `daemon/hnc_httpd/hnc_httpd` after applying this patch, because both Go API code and embedded remote WebUI assets changed.

Rebuild/validate `bin/hotspotd` as usual if your CI builds all native components; hotfix5 itself did not change hotspotd C code.
