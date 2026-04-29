# HNC v5.2.0-rc1.18

## 目标

rc1.18 是 v5.2 stats 灰度观察链路的小修版本。

目标只有一个：让 `stats_v52_gray_observe.sh text` 普通观察模式在 shadow raw 已经存在时自动刷新当天 `stats_shadow_rollup.sh`，避免报告读取旧的 `stats_shadow_daily.jsonl`，从而出现 raw 已经有真实流量、daily 仍显示 0 的误导结果。

## 改动

- `bin/stats_v52_gray_observe.sh`
  - 新增默认开启的自动 shadow rollup：`HNC_V52_OBSERVE_AUTO_ROLLUP=1`。
  - 当 `data/stats_shadow_raw.jsonl` 已存在且未显式请求 sample 时，自动执行当天 rollup。
  - 自动 rollup 后强制刷新 readiness / gray report / review bundle 缓存。
  - 新增输出字段：
    - `auto_rollup_used`
    - `auto_rollup_date`
  - 保留 `HNC_V52_OBSERVE_SAMPLE=1` 的显式采样模式。
  - 可用 `HNC_V52_OBSERVE_AUTO_ROLLUP=0` 关闭自动 rollup。

- `test/unit/test_stats_v52_gray_observe.sh`
  - 增加默认观察模式下 raw 存在时自动调用 rollup 的回归测试。
  - 确认自动 rollup 不会触发 shadow sample。

- 版本更新：
  - `v5.2.0-rc1.18`
  - `versionCode=520028`

## 安全边界

本版本不做以下事情：

- 不启用 v5.2 RC。
- 不切换默认 stats source。
- 不改 tc / iptables 核心限速规则。
- 不改 watchdog。
- 不改限速 / 延迟 / 黑名单 / 白名单逻辑。
- legacy stats 仍然保持默认源。

## 测试建议

安装 rc1.18 后，在热点开启、有客户端流量的情况下执行：

```sh
su -c '
sh /data/local/hnc/bin/stats_v52_gray_observe.sh text
cat /data/local/hnc/run/stats_v52_gray_observe.md | head -160
'
```

重点确认：

```text
auto_rollup_used=true
shadow_daily_total_rx 大于 0 或符合当前真实流量
shadow_daily_total_tx 大于 0 或符合当前真实流量
traffic_state=traffic_seen
default_source=legacy
rc1_enabled=false
rc_enabled=false
```

如果需要关闭自动 rollup 对比旧行为：

```sh
HNC_V52_OBSERVE_AUTO_ROLLUP=0 sh /data/local/hnc/bin/stats_v52_gray_observe.sh text
```
