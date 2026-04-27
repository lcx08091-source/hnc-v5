# HNC v5.1.0-rc1 hotfix21.1

## 目标

在 v5.2 stats 重构前继续补只读诊断能力，重点观察 `stats_sample.sh` 依赖的 `devices.json` IP → MAC 身份映射，提前发现 DHCP IP 复用、stale devices、重复 IP、raw stats 中未知 MAC 等风险。

## 改动

- 新增 `bin/stats_identity_diag.sh`。
  - 默认输出 JSON。
  - 支持 `text/status` 模式。
  - 只读检查 `devices.json` 和最近 `stats_raw.jsonl`。
  - 检测 duplicate IP、key mac / field mac 不一致、raw stats 近期未知 MAC。
- `json_diag_bundle.sh` 收集 stats identity 诊断输出。
- `json_health_panel.sh` 输出 stats identity 原始状态。
- `ci_preflight.sh` 检查 `stats_identity_diag.sh` 存在与可执行。
- 新增 `test/unit/test_stats_identity_diag.sh`。

## 不改动

- 不改 stats 采样逻辑。
- 不改 stats rollup 逻辑。
- 不改 JSON 写入逻辑。
- 不改 tc / iptables / watchdog。
