# HNC v5.2.0-rc1.19

## 目标

修复 v5.2 shadow daily rollup 在同一天遇到 iptables 计数器回退或 `0/0` 样本时，错误把已经累计出的 daily 流量清零的问题。

## 背景

实机 rc1.18 灰度观察发现，同一 MAC 当天 raw 样本可能出现：

```text
227138 / 3952
→ 56021628 / 48556148
→ 201628922 / 149591042
→ 0 / 0
```

旧 rollup 使用 `latest - baseline`，最后一条 `0/0` 会被识别为 counter reset，但仍可能把当天 daily 写成 `rx=0 tx=0`。

## 修复

- `stats_shadow_rollup.sh` 改为按同一天样本分段累加：
  - 第一条同日样本作为 `first_sample` baseline；
  - 正常递增时累加差值；
  - 计数器回退时标记 `counter_reset`；
  - 回退到非 0 时从新段继续累加当前值；
  - 回退到 `0/0` 时只标记 `zero_reset_preserved`，不清除已有累计值。
- 增加 rc1.19 回归测试，覆盖实机观测到的 `201628922/149591042 -> 0/0` 场景。

## 不变项

- 不启用 v5.2 RC。
- 不切换默认 stats source。
- 不改 tc / iptables 核心限速规则。
- 不改 watchdog。
- 不改限速 / 延迟 / 黑名单 / 白名单。
- legacy stats 仍然是默认源。

## 版本

- `version=v5.2.0-rc1.19`
- `versionCode=520029`
