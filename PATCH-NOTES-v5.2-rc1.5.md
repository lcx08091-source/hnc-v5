# HNC v5.2.0-rc1.5

## WebUI booting 白屏保护

本补丁只修改 WebUI 首屏初始化兜底，不改 tc / iptables / watchdog / 限速 / 延迟 / stats 数据源切换逻辑。

### 修复点

- `webroot/index.html`：新增 `finishBootVisual()`，确保以下路径都会移除 `html.booting`：
  - 非 KSU/SukiSU WebUI 环境提前返回
  - `/api/health` 不可达/超时提前返回
  - `init()` 未捕获异常
  - 正常初始化完成
- 新增 8 秒兜底超时，避免 WebView/JS 异常导致 `booting` 永久残留。
- `html.booting` 状态下为玻璃卡片、搜索栏、工具栏、设备卡片增加可见边框和实体背景，避免浅色主题下“白底白卡片”看起来像白屏。

### 版本

- `version=v5.2.0-rc1.5`
- `versionCode=520015`
