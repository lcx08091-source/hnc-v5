# HNC v5.2.0-rc1.9

## Purpose

Fix the WebUI startup transport behavior discovered on SukiSU/ColorOS:

- rc1.8 proved that the WebUI can render safely when it does not auto-call `window.ksu.exec()` during first paint.
- The same device reported that HTTP direct fetch fails, while manual "force bridge" works.
- rc1.9 keeps the safe first-paint behavior, then performs exactly one delayed automatic KSU/SukiSU bridge attempt.

## Changes

- Keep WebUI skeleton rendering before any backend request.
- Try WebView HTTP direct first.
- If direct HTTP fails, wait 1.2 seconds after first paint and attempt KSU/SukiSU bridge once.
- If delayed auto bridge succeeds, continue normal initialization and device refresh.
- If delayed auto bridge fails, keep the UI usable and show manual retry / force bridge buttons.
- Once bridge is confirmed, prefer bridge for subsequent GET requests to avoid waiting for direct fetch failures on every API call.
- Keep manual "force bridge" path for debugging.

## Not changed

- No tc changes.
- No iptables changes.
- No watchdog changes.
- No limit / delay / blacklist / whitelist logic changes.
- No stats source switching behavior changes.

## Version

- version: v5.2.0-rc1.9
- versionCode: 520019
