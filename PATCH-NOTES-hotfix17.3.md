# HNC v5.1.0-rc1-hotfix17.3

## 修复
- 强制 `service.sh` 在每次模块服务启动时把 `MODDIR` 里的最新 `bin/`、`webroot/`、`api/` 与 `daemon/hnc_httpd/hnc_httpd` 同步到 `/data/local/hnc`，防止 WebUI 已更新但运行中的 `hnc_httpd` 仍是 hotfix4。
- `tc_manager.sh` 统一使用稳定的 `/system/bin/tc` / `/system/bin/ip` 优先路径，避免 KSU/SukiSU/Termux PATH 解析到 busybox/toybox 版 `tc`，导致 `invalid argument 'root' to 'command'`。
- MIUI14 `qdisc mq root` 设备上，mq 子队列只做一次 best-effort 探测；失败后直接走已验证的 root HTB fallback：`tc qdisc replace dev <iface> root handle 1: htb default 9999`，不再反复尝试 `parent :1/0:1`。
- watchdog 在热点进入 ACTIVE 后重新运行 `capability_probe.sh`，避免 service 早期探测在热点未就绪时写出 unknown/false 能力。
- `restore_rules` 对离线且 IP 不在当前热点网段的旧规则直接跳过 TC restore，避免旧 NAT 段规则持续占锁并干扰当前设备限速。
- `daemon/hnc_httpd/build.sh` 仅在存在 `vendor/` 时使用 `-mod=vendor` 与离线代理；没有 vendor 时允许 CI 下载 Go modules，防止打包继续沿用旧二进制。

## 预期
- 小米10 / MIUI14：下行限速与 egress-only 延迟应走 root HTB/netem fallback；上行仍因 IFB/mirred/police 不可用而保持禁用。
- `/api/live`、`/api/capabilities`、`/api/metrics` 应在重新编译并同步新版 `hnc_httpd` 后正式可用，不再依赖前端 404 降级。

