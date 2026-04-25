# HNC v5.1.0-rc1 hotfix9

## 目标

- 解决长期使用后离线 rule-only 设备默认挤满设备列表的问题。
- 保留 hotfix3 的设计: 离线但有规则的设备仍然可以管理,只是默认不展示。

## 本轮改动

### 本机 KSU WebUI

- 设备列表新增过滤器: `只看在线` / `显示全部` / `只看离线规则`。
- 默认值为 `只看在线`,并持久化到 `localStorage.hnc_device_filter`。
- 列表计数仍显示 `在线 / 总数`,方便知道有多少离线历史设备被隐藏。
- 批量全选只选择当前可见卡片,避免默认模式下误批量操作离线历史规则。

### 远程 WebUI

- 同步新增过滤器,默认 `只看在线`,持久化到 `localStorage.hnc_remote_device_filter`。
- 远程静态资源由 `go:embed` 打进 `hnc_httpd`,因此修改 `daemon/hnc_httpd/web/*` 后需要重新编译 `hnc_httpd`。

## 未包含

- 本轮没有加入自动清理 `rules.json` 的后端逻辑。
- `last_seen_persist`、`cleanup_stale_rules.sh`、`json_set.sh device_remove` 建议放到 hotfix10,避免本轮同时引入持久化删除逻辑风险。

## 需要重新编译

- 本机 WebUI: 不需要。
- 远程 WebUI: 需要重新编译 `daemon/hnc_httpd/hnc_httpd`,因为远程前端通过 `embed.go` 嵌入。
