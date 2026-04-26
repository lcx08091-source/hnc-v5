# HNC hotfix17.4 patch notes

## 修复目标

hotfix17.3 已经确认新版 `hnc_httpd` 正常启动，`/api/live`、`/api/capabilities`、`/api/metrics` 可用；同时 root HTB fallback 曾经成功。

但真机 debug 显示：系统/热点重建后 `wlan1` root qdisc 会回到 `mq`，后续 `set_limit` / `set_delay` 仍直接向 `1:*` 写 class/netem，导致：

- `tc set_limit failed`
- `netem apply failed`
- `ensure_device_class: class add failed`

## 本次改动

- 新增 `egress_htb_tree_ready()`：检查热点口是否已有 `qdisc htb 1:` 和 `class htb 1:1`。
- 新增 `ensure_egress_htb_ready()`：如果 HTB 树缺失，立即调用 `init_tc <iface>` 重建 root HTB fallback。
- `set_limit` 启用下行限速前先执行 JIT HTB 自愈。
- `set_delay` 启用延迟/抖动/丢包前先执行 JIT HTB 自愈。
- `ensure_device_class` 在 class add/change 失败时自动重建 HTB 后重试一次。
- `set_rate_only` / `set_netem_only` 失败后走一次自愈重试。

## 预期效果

在小米10 / MIUI14 上，如果 `wlan1` 又从 HNC root HTB 回到 ROM `mq`：

1. 用户点击“应用限速”或“注入延迟”；
2. HNC 发现 HTB 树缺失；
3. 自动走已验证成功的 root HTB fallback；
4. 重新创建 class / leaf netem；
5. 再写入限速或延迟规则。

上行限速仍保持禁用，因为 IFB/mirred/police 仍不可用。
