# HNC v5.3.0-rc25.0 — DPI 规则库增强 / 未识别域名助手

## 重点

- 扩充内置 `data/dpi_rules.json`：更多游戏、系统服务、广告/统计 SDK、云/CDN 低可信线索。
- WebUI DPI 页新增“未识别域名助手”：从当前 DNS/SNI Top 提取补库线索。
- 支持一键生成可编辑规则模板到规则库编辑框，再由现有“导入规则库”写入 `/data/local/hnc/etc/dpi_rules.json`。
- 保持只读 DPI：不修改限速、iptables、tc、DNS 或 offload。
- nDPI Lab 仍为短时采样实验引擎，不替代 Go `hnc_dpid` 主线。

## 使用

1. 连接热点设备打开 App/网页。
2. WebUI → DPI → 未识别域名助手。
3. 点击“模板”或“生成模板到规则编辑框”。
4. 编辑 `app`、`category`、`suffixes` 后点击“导入规则库”。
