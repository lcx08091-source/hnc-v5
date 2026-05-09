# HNC v5.3.0-rc8

P0 stability sweep based on rc7 bug audit.

- Fix watchdog httpd bind drift detector: wildcard 0.0.0.0 listener is no longer killed on hotspot IP churn; only remote toggle transitions relaunch httpd.
- Stop json_set.sh hnc_json fallback warnings from leaking to stderr and poisoning daemon CombinedOutput parsing.
- Add hnc_json to post-fs-data.sh/service.sh chmod fallback loops.
- Preserve recently seen devices as status=stale for 180s during shell ARP scans to avoid transient devices.json disappearance.
- Add WebUI double-confirm before blacklisting gateway-like or wlan0 devices.

Version: v5.3.0-rc8 / versionCode 530008.
