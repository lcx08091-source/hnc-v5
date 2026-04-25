# HNC v5.1.0-rc1 hotfix7

## 目标

修复 realme GT 7 Pro / ColorOS 16 / kernel 6.6 上点击限速后再注入延迟失败、限速 class 被破坏、restore 连续失败占用 gate_lock 导致 WebUI 卡顿的问题。

## 关键修复

- `bin/tc_manager.sh`：`ensure_device_class()` 已存在 class 时不再执行 `tc class del + tc class add`。
- 改为优先使用 `tc class change` 原地刷新 rate/ceil/burst/cburst，避免 ColorOS/oplus_netd 环境中 del 成功但 add 失败造成断头 class。
- leaf netem 已存在时优先 `tc qdisc change`，不存在时才 `add`；change 失败时不删除 class。
- `restore_rules()` 增加连续失败保护：连续 2 台恢复失败即中止本轮 restore，避免长时间占用 gate_lock 造成 UI 操作超时。

## 是否需要重新编译

不需要。hotfix7 主修为 shell 脚本修复，未替换 Go/C/BPF 二进制。
