# HNC v5.3.0-rc17

目标：收尾 RC16 的 UI 刷新慢、进程数量误判、hotspotd 偶发重复实例。

## 改动

- DPI 页面：等待接口 / 重绑中 / 后端不可达时 1 秒快速刷新，正常抓包后降回 4 秒。
- DPI 页面：新增“进程诊断”卡，显示主实例数量和总 shell 数。
- 新增 `bin/rc17_process_health.sh`，用于 WebUI 和 Termux 快速判断 HNC 关键进程状态。
- service.sh / watchdog.sh：增加 `prune_duplicate_hotspotd`，保留 pidfile 指向的 hotspotd，清理多余实例。
- 释放并重启、手动 DPI 重绑后，WebUI 自动进入短时间快速刷新窗口。

## 测试重点

1. DPI 页面从“等待接口就绪”恢复到“正常 · 抓包中”的刷新速度。
2. `hnc_httpd` / `hnc_dpid` / `hotspotd` 是否保持 1 个。
3. `watchdog.sh` / `hnc_dpid_guard.sh` 是否只显示一个主实例，子 shell 不再被 UI 当成异常。
4. 点“释放并重启资源”后 5–15 秒内页面是否自动恢复。

版本：`v5.3.0-rc17 / 530017`。
