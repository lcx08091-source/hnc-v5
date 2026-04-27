# HNC v5.1.0-rc1 hotfix18.6

## 目标

给 hotfix18 JSON 专项增加一个低风险、非侵入式 WebUI 辅助入口，方便用户在 KSU/SukiSU WebView 内查看 JSON 健康状态并一键导出诊断包。

## 改动

- 新增 `bin/json_health_panel.sh`
  - 只读汇总 `json_doctor status`、`json_guard`、JSON 备份数量、TC 状态快照和能力探测文件。
  - 输出适合 WebUI 渲染的 JSON。

- 新增 `bin/json_export_for_web.sh`
  - 调用 hotfix18.5 的 `json_diag_bundle.sh`。
  - 返回生成的 `/sdcard/Download/hnc-json-debug-*.tar.gz` 路径。

- 新增 `webroot/json-health.html`
  - 独立诊断页面，不覆盖主 `index.html`。
  - 使用原 WebUI 近似的深色玻璃卡片、圆角、蓝色渐变按钮风格。
  - 支持刷新 JSON 健康状态、一键导出 JSON 诊断包。

## 设计取舍

此版本暂不直接修改主 `webroot/index.html`，避免在用户频繁 hotfix 后覆盖最新主界面。需要主界面入口时，可以后续在确认最新 `index.html` 后把此页面嵌入“设置/诊断”区域。

## 风险

低。新增页面和脚本默认只读；只有导出诊断包会写入 `/sdcard/Download` 和 `/data/local/hnc/run/json_diag_last.txt`，不会修改 live JSON。
