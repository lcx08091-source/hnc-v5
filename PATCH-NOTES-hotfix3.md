# HNC v5.1.0-rc1 hotfix3

Focus: UI 卡顿和远程访问数据不同步。

## 修复点

1. 远程 dashboard `daemon/hnc_httpd/web/app.js`
   - `/api/devices` 和 `/api/stats` 增加 in-flight guard，上一轮未完成时跳过普通轮询。
   - 增加请求序号，慢响应/旧响应不再覆盖新数据。
   - 设备列表增加签名比对，数据未变化时不重复整表 `innerHTML` 重绘。
   - 设备选择下拉只在 MAC 集合变化时重建。
   - 页面隐藏时暂停轮询，统计页打开时才刷新统计。
   - 写操作成功后使用强制刷新，避免旧轮询响应把刚写入的状态覆盖回去。

2. 本地 KSU WebUI `webroot/index.html`
   - `apiGet()` 的 curl 增加 `Cache-Control: no-cache`。
   - `fetchDevices()` 增加 in-flight guard 和请求序号，防止 `curl --max-time 10` 堆积多个 KSU exec 导致 WebView 卡顿。
   - `tickPoll()` 增加 busy guard 和 `document.hidden` 检查，避免后台/慢请求叠加。
   - 所有写操作后的刷新改为 `fetchDevices({force:true})`，保证写后状态优先生效。
   - 远程访问 URL 卡片只按在线设备数量判断，不再被 rules-only 离线设备误判为“运行中”。
   - `limited` 展示逻辑修正为 `limit_enabled && (down_mbps > 0 || up_mbps > 0)`，避免 0 速率/清除后误显示限速。

3. Go httpd API
   - `writeJSON()` / `writeActionResp()` 以及 v5 GET API 增加 `Cache-Control: no-store`，避免浏览器/WebView 缓存动态状态。
   - `/api/devices` 现在会把 `rules.json.devices` 和 `blacklist` 里存在、但 `devices.json` 已经没有的设备作为离线条目返回。这样远程 UI 可以看到离线但仍有规则/黑名单的设备，避免“规则还在但远程 UI 看不到”的状态不同步。

## 需要重新编译

修改了 Go 源码：

- `daemon/hnc_httpd/server.go`
- `daemon/hnc_httpd/api_v5.go`
- `daemon/hnc_httpd/action.go`

因此需要重新编译 `daemon/hnc_httpd/hnc_httpd`，否则 Go 侧 no-store 和 rules-only 设备返回不会进入运行时。

Web 前端文件在重新打包后会随源码更新；如果你的构建脚本使用 embed，需要重新编译 Go 让 `daemon/hnc_httpd/web/app.js` embed 进去。

## 本地校验

- `node --check daemon/hnc_httpd/web/app.js` 通过。
- 从 `webroot/index.html` 抽取内联脚本后 `node --check` 通过。
- `gofmt` 已执行。
- `go test` 未能在当前环境运行，因为本地 Go 尝试下载 Go 1.25 toolchain，但沙盒无外网。
