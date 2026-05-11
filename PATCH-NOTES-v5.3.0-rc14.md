# HNC v5.3.0-rc14

Focus: stabilize rc13 resource restart and DPI backend behavior.

Changes:
- Rename the release-resource flow semantics to a safer restart-oriented maintenance action.
- WebUI now uses a normal confirmation dialog for “释放并重启资源”; it no longer asks the user to type RELEASE.
- service.sh now force-stops old hnc_httpd, removes the runtime copy, copies the module binary again, chmods it, and verifies the DPI API route strings when possible.
- hnc_dpid_guard.sh now uses a dedicated dpid_guard.pid and single-instance lock ownership so duplicate launcher attempts cannot tear down the active guard.
- watchdog.sh checks dpid_guard.pid when the guard is enabled and no longer relaunches extra guard instances because dpid.pid belongs to the capture child.
- cleanup.sh now kills dpid_guard processes and pidfiles during restart/full cleanup.
- artifact_sanity_check.sh now verifies /api/dpi_state, /api/dpi_probe, apiDPIState, and apiDPIProbe are present in hnc_httpd.

Validation target:
- After release-and-restart, /api/live, /api/dpi_state, and /api/dpi_probe should return JSON, not 404.
- Only one root hnc_dpid_guard supervisor group should remain after cleanup/restart.
