# HNC v5.1.0-rc1 hotfix4

Focus: low-risk async/concurrency hardening for UI smoothness and remote state consistency.

## Changes

1. Remote dashboard (`daemon/hnc_httpd/web/app.js`)
   - Added bounded fetch transport using `AbortController` with timeout fallback.
   - `/api/devices` and `/api/stats` now fail fast instead of leaving in-flight flags stuck forever on bad mobile links.
   - `/api/action` uses a longer bounded timeout and schedules a convergence refresh after timeout.
   - Added per-device/global action de-duplication so fast repeated taps do not queue duplicate writes.

2. On-device KSU WebUI (`webroot/index.html`)
   - Added per-device/global `apiAction` de-duplication around the curl bridge.
   - Prevents repeated taps/toggles from stacking multiple `ksu.exec curl` POSTs for the same device/action group.

3. Go HTTP daemon (`daemon/hnc_httpd/server.go`, `daemon/hnc_httpd/action.go`)
   - Added coarse `stateMu` RW lock.
   - All `/api/action` write chains are serialized. This prevents concurrent tc/iptables/json_set operations from interleaving.
   - `/api/devices` takes the read side of the same lock, so it no longer observes half-written state from httpd-originated actions.
   - Logs when an action waited behind another write for more than 200ms.

## Deliberate non-changes

- Did not convert tc/iptables shell operations into a background worker queue. That would be a larger architectural change with higher risk of ordering bugs.
- Did not parallelize per-device rule application. Correct operation order is prioritized over raw write throughput.

## Runtime note

- WebUI file changes take effect after reinstall/reload.
- Go changes require rebuilding `daemon/hnc_httpd/hnc_httpd` for runtime effect.

## Suggested checks

- Open remote dashboard from two browsers and repeatedly click limit/delay on the same device: only one write should run at a time.
- During a write action, `/api/devices` should wait and then return converged state instead of a partial rules.json/devices.json merge.
- On unstable connection, dashboard should show a timeout/error rather than staying permanently stuck in loading state.
