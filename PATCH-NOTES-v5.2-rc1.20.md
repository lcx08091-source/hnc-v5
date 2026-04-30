# HNC v5.2.0-rc1.20

## 目标

修复 rc1.19 验证中发现的两个 gray observe 展示问题：跨日后自动 rollup 选错日期，以及已有正流量时仍显示 `observed_zero_traffic`。

## 背景

实机验证中，真实 shadow raw 数据仍在 `2026-04-29`，但设备当前日期已经到 `2026-04-30`。旧的 `stats_v52_gray_observe.sh` 自动 rollup 使用 `date +%F`，导致普通观察报告 rollup 了没有 raw 数据的当天，而不是最新 raw 样本所在日期。

同时，在手动按 raw 日期 rollup 后，报告已经能读到正的 daily total，但 `shadow_quality` 仍可能保留为 `observed_zero_traffic`。

## 修复

- `stats_v52_gray_observe.sh` 新增 `latest_raw_date()`，自动 rollup 优先使用 `stats_shadow_raw.jsonl` 中最新样本的 `date`。
- 显式 sample 模式也使用最新 raw 日期做 rollup，避免跨日采样后滚错日期。
- 当 raw 或 daily 总流量大于 0 时，observe 会把 `traffic_state` 归一为 `traffic_seen`，并把 stale 的 `observed_zero_traffic` 修正为 `observed`。
- 增加 rc1.20 回归测试，覆盖 latest raw date rollup 和 positive totals quality override。

## 不变项

- 不启用 v5.2 RC。
- 不切换默认 stats source。
- 不改 tc / iptables 核心限速规则。
- 不改 watchdog。
- 不改限速 / 延迟 / 黑名单 / 白名单。
- legacy stats 仍然是默认源。

## 版本

- `version=v5.2.0-rc1.20`
- `versionCode=520030`
