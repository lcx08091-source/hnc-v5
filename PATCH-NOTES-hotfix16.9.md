# HNC v5.1.0-rc1 hotfix16.9

## 目标

修复 MIUI14 / 小米10 等环境中 `tc_htb=false`、`tc_netem=false` 时 WebUI 仍允许点击限速/延迟，导致 `hnc_httpd` 超时、`tc_manager` 反复尝试失败的问题。

## 主要改动

- WebUI 根据 `run/capabilities.json` 精确禁用不支持的控制项：
  - `tc_htb=false`：禁用下行/上行限速输入和“应用限速”按钮。
  - `tc_netem=false` 或 `tc_htb=false`：禁用延迟、抖动、丢包输入和“注入延迟”按钮。
  - 清除按钮保留，方便清掉历史规则状态。
- Go action 层增加 capability gate：
  - `rule_set` 在 `tc_htb=false` 时快速返回 `unsupported`，不再调用 shell/tc。
  - `delay_set` 在 `tc_netem=false` 或 `tc_htb=false` 时快速返回 `unsupported`。
- `tc_manager.sh` 增加 runtime capability gate：
  - `init_tc`、`set_limit`、`set_delay` 在不支持时快速跳过。
  - `restore_rules` 会跳过不支持的限速/延迟规则，避免连续失败触发恢复风暴。
- `watchdog.sh` 增加 `tc_htb=false` 降级逻辑：
  - 健康检查不再要求 root HTB qdisc。
  - full restore / first init / interface migrate 不再反复执行 TC init/restore。
- 设置页降级：
  - `/api/metrics` 404 时显示“兼容模式”，不再刷失败。
  - `/api/capabilities` 404 时读取本地 `run/capabilities.json`。

## 预期效果

在 TC 能力不足的 ROM 上，HNC 会明确显示“限速/延迟不支持”，并避免点击后长时间卡死或后端无响应。设备识别、黑白名单、WebUI、远程访问仍可继续使用。
