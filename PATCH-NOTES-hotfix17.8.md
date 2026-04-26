# HNC hotfix17.8

安全与稳定性小修，吸收审查报告中低风险高收益项。

## 变更

- `daemon/hnc_httpd/auth.go`：`LastSeen > 0` 时才执行 hard-expire 判断。
- `daemon/hnc_httpd/middleware.go`：`auth_required` 缺失/类型错误 fail-closed；`/api/logs` 远程访问强制鉴权。
- `daemon/hnc_httpd/action_v5.go`：修正热点密码错误文案，避免 UTF-8 支持与 ASCII 文案冲突。
- `daemon/hotspotd/mdns_worker.c`：stop 时立即清空 pending queue 并退出。
- `bin/watchdog.sh`：`httpd.pid` 增加 cmdline 校验，避免 PID 复用。

## 风险

- 远程未配对访问 `/api/logs` 将返回 401，这是预期安全收紧。
- 本机 KSU WebUI loopback 无 Origin/Referer 的请求仍兼容。
