# HNC v5.2.0-rc1.16

## 目标

让 v5.2 灰度报告、readiness 和 review bundle 正确认出 rc1.15 打通的 shadow raw / shadow daily 数据，并给出 legacy/shadow 对比状态。

## 变更

- `bin/stats_migration_readiness.sh`
  - 新增 `shadow_state`：
    - `no_shadow_data`
    - `shadow_raw_seen`
    - `shadow_rollup_seen`
  - 新增 `shadow_quality`：
    - `missing`
    - `warmup`
    - `observed`
    - `observed_zero_traffic`
    - `warn_no_devices`
    - `warn_no_daily_samples`
  - 新增 raw/daily 指标：
    - `shadow_latest_ts`
    - `shadow_raw_devices`
    - `shadow_raw_total_rx`
    - `shadow_raw_total_tx`
    - `shadow_daily_devices`
    - `shadow_daily_samples`
    - `shadow_daily_total_rx`
    - `shadow_daily_total_tx`
  - 新增 legacy/shadow 对比摘要：
    - `compare_quality`
    - `compare_total_keys`
    - `compare_matched_keys`
    - `compare_missing_in_legacy`
    - `compare_missing_in_shadow`
    - `compare_mismatched_keys`
    - `compare_unique_macs`

- `bin/stats_v52_gray_report.sh`
  - 在 text / markdown / json 中展示 shadow 数据识别和 legacy/shadow 对比摘要。
  - 继续保持 gray report 只读，不启用 RC、不切换默认 stats source。

- `bin/stats_v52_review_bundle.sh`
  - 在脱敏审查包中展示 shadow / compare 摘要。
  - 便于发给 Claude / Gemini / GPT 交叉审查时快速判断 shadow 是否已经进入可观察状态。

- `test/unit/test_stats_shadow.sh`
  - 增加 rc1.16 readiness / gray report / review bundle 回归测试。

## 安全边界

本补丁不修改：

- tc / iptables 核心限速规则
- watchdog
- limit / delay
- 黑名单 / 白名单
- 默认 stats source
- v5.2 stats RC enable 状态

legacy stats 仍然是默认统计源，v5.2 shadow 仍然只用于灰度观察。

## 版本

- version: `v5.2.0-rc1.16`
- versionCode: `520026`
