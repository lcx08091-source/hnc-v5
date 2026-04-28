# HNC v5.2.0-rc1.6

## WebUI init 同步启动兜底

本补丁只修改 WebUI 首屏启动链路，不改 tc / iptables / watchdog / 限速 / 延迟 / 黑白名单 / stats 数据源切换逻辑。

### 修复点

- `webroot/index.html`：不再用 `setTimeout(0)` 调度 `init()`。
- `init()` 改为在当前主 script 内直接启动，避免部分 ColorOS / Android WebView 出现 timer / rAF / DOMContentLoaded 不再调度后，WebUI 永远停在“等待刷新”。
- `requestAnimationFrame` 仅保留为可选性能标记，并加 `try/catch`，不参与关键启动路径。
- `finishBootVisual()` 立即移除 `html.booting`，不再依赖双 `requestAnimationFrame`。
- 保留 rc1.5 的 booting 可视兜底 CSS 和 8 秒兜底超时。

### 版本

- `version=v5.2.0-rc1.6`
- `versionCode=520016`
