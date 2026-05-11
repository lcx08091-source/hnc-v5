# HNC v5.3.0-rc13 — 释放资源安全化 + DPI 快速重绑

## 背景

rc12 真机验证发现两个问题：

1. WebUI 点击「释放所有资源」后会执行纯 `cleanup.sh all`，杀掉 `hnc_httpd` / `watchdog` / `hotspotd` 等后台进程。退出重进后前端还在，但本地后端不再监听，导致自动 bridge 失败、`Failed to fetch`。
2. `hnc_dpid` 在热点接口 `wlan2` 还没完全 `UP` 时启动，可能进入 `recvfrom: network is down` / `盲模式 · 未抓包`，需要用户手动重启 DPI 才恢复。

## 改动

### 1. 释放资源改为 safe release

- WebUI 的 `cleanup_all` action 不再执行纯 `cleanup.sh all`。
- 改为 `cleanup.sh safe_release`：清理 tc/iptables、停止子进程，然后由 `cleanup.sh` 直接 fork `service.sh` 自动拉起后端。
- 纯 `cleanup.sh all` 保留给模块禁用 / 卸载 / 手动彻底释放场景。
- `cleanup.sh` 增加 `safe_release` alias，等价于安全重启资源。
- cleanup pid 清理列表加入 `dpid.monitor` / `dpid.child` / `dpid`，避免 DPI guard 或 child 残留。

### 2. WebUI 危险操作防误点

- 「释放所有资源」改名为「释放并重启资源」。
- 文案明确提示：日常清限速请用「清空所有规则」。
- 执行前需要输入 `RELEASE` 二次确认。
- 执行后不再把页面替换成离线提示，而是等待后端恢复并自动刷新。
- bridge 失败卡片新增「重新拉起服务」按钮：后端已死时可直接通过 KernelSU/SukiSU bridge 执行 `service.sh`。

### 3. 新增 `bin/hnc_dpid_guard.sh`

`hnc_dpid_guard.sh` 作为 `hnc_dpid` 的轻量守护包装器：

- 热点接口不存在或未 `IFF_UP` 时，不立即启动抓包，而是写入「等待接口就绪」状态。
- 启动窗口使用高频短 backoff：`0 / 100 / 200 / 500 ms / 1 s / 1.5 s / 2 s`。
- 长时间未就绪后降为 3 秒兜底检查，避免耗电和刷日志。
- 尝试使用 `ip monitor link address` 监听 netlink 事件，接口变化时立即 kill child 并重绑。
- 如果 `dpi_state.json` 出现 `network is down`，guard 会自动重启 capture child，避免 rc12 的永久盲模式。

### 4. service/watchdog 接入 DPI guard

- `service.sh` 优先启动 `bin/hnc_dpid_guard.sh`。
- 如果 guard 不存在，仍回退到直接启动 `bin/hnc_dpid`。
- `watchdog.sh` 的 dpid 存活检查同样优先拉起 guard。

### 5. DPI 页面状态更清晰

- `blind_reason` 包含 `waiting for hotspot interface` 或 `network is down` 时，UI 显示「等待接口就绪」。
- 检测到 rebind/iface changed 时显示「重绑中」。
- 避免把正常的接口切换窗口误报成严重失败。

### 6. 新增 rc13 自检脚本

新增：

```sh
sh /data/local/hnc/bin/rc13_release_resource_selfcheck.sh
```

检查：

- `hnc_httpd` / `watchdog` / `hotspotd` / `dpid` pid 是否存活
- `/api/health` / `/api/live` / `/api/devices` 是否可访问
- `dpi_state.json` 模式和接口状态
- 热点接口是否存在并为 `IFF_UP`

## 版本

- `version=v5.3.0-rc13`
- `versionCode=530013`
