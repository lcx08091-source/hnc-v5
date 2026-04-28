# HNC v5.2.0-rc1.8

Scope: WebUI boot/bridge safety only.

## Why

rc1.7 proved the first paint works, but on some SukiSU/ColorOS WebView builds the first automatic `window.ksu.exec(curl ...)` can still synchronously block the WebView. JS timeouts cannot fire when the bridge call itself blocks the UI thread.

## Changes

- Prefer browser `fetch()` to `http://127.0.0.1:8444` for automatic boot-time health checks.
- Disable automatic KSU bridge transport during WebUI boot.
- Only allow KSU bridge transport after explicit user action: `强制桥接`.
- Keep the first-screen skeleton and bridge status card visible even when backend probing fails.
- Change default retry to `重试直连` so it does not call bridge automatically.
- Disable the legacy embedded JSON-health entry auto probe on the main WebUI because it used a raw `window.ksu.exec(...).then(...)` path outside the guarded transport layer.

## Not changed

- No tc/iptables/watchdog changes.
- No speed-limit/latency/blacklist/whitelist behavior changes.
- No stats source switch changes.
