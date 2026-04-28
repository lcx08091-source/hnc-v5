# HNC v5.2.0-rc1.7

WebUI white-screen/等待刷新 guard.

## What changed

- Keep WebUI skeleton rendering before any KSU/SukiSU bridge API call.
- Do not call `renderBars()` before `/api/health`, because `renderBars()` itself reaches `/api/stats` and can hit the same bridge hang.
- Add JS-level timeout around `apiGet()` and `apiAction()` transport calls.
- Add a visible persistent bridge status card with a retry button.
- Yield to first paint before the first bridge call, so a blocking bridge call cannot hide the skeleton UI.

## Not changed

- No TC rule changes.
- No iptables rule changes.
- No watchdog changes.
- No limiter/delay/blacklist/whitelist behavior changes.
- No v5.2 stats source default switch.
