# HNC v5.2.0-rc1.17

## 目标

进入 v5.2 stats 实机灰度观察期：不启用 v5.2 stats、不切换默认 source，只新增一个只读观察助手，把 rc1.16 已经可见的 shadow raw/daily、legacy/shadow 对比、设备状态和真实流量状态汇总成一份可直接交叉审查的报告。

## 变更

- 新增 `bin/stats_v52_gray_observe.sh`
  - 默认只读，不启用 RC、不切换 stats source、不修改 tc/iptables/watchdog/限速/延迟。
  - 汇总：
    - `shadow_state`
    - `shadow_quality`
    - `traffic_state`
    - `shadow_raw_lines`
    - `shadow_daily_lines`
    - `shadow_daily_samples`
    - `shadow_latest_ts`
    - `sample_age_seconds`
    - shadow raw/daily rx/tx 总量
    - `compare_quality`
    - legacy/shadow matched/missing/mismatched 数量
    - devices.json 中设备总数、带 IP 数、online/blocked/active 数量
  - 输出：
    - `/data/local/hnc/run/stats_v52_gray_observe.json`
    - `/data/local/hnc/run/stats_v52_gray_observe.txt`
    - `/data/local/hnc/run/stats_v52_gray_observe.md`
  - markdown 内置 rc1.17 实机灰度 checklist。

- 可选显式采样模式
  - 默认不采样，仅汇总已有状态。
  - 设置 `HNC_V52_OBSERVE_SAMPLE=1` 时，才主动跑一次 `stats_shadow_sample.sh` 和当日 `stats_shadow_rollup.sh`。
  - 设置 `HNC_V52_OBSERVE_REFRESH=1` 时，才刷新 readiness / gray report / review bundle 缓存。

- 新增回归测试
  - `test/unit/test_stats_v52_gray_observe.sh`

## 安全边界

本版本保持以下行为不变：

- legacy stats 仍是默认 source。
- v5.2 RC 默认不启用。
- 不自动切换 WebUI stats source。
- 不修改 tc / iptables 核心规则。
- 不修改 watchdog。
- 不修改限速 / 延迟 / 黑名单 / 白名单核心逻辑。

## rc1.17 实机观察建议

安装后建议依次测试：

1. 单设备连热点刷网页后，shadow rx/tx 是否增长。
2. 单设备测速后，legacy/shadow 对比是否仍处于可解释状态。
3. 设备断开再连接后，MAC 归属是否稳定。
4. 热点重启后，shadow sample/rollup 是否仍能生成。
5. blocked 设备状态是否能被报告识别，不误判为 source 切换失败。
6. 多设备同时连接时，devices_total 与 shadow device 数是否大致一致。
7. 跨日或手动指定日期 rollup 后，daily 样本是否继续累加。

## 推荐验证命令

```sh
su -c '
HNC_V52_OBSERVE_REFRESH=1 sh /data/local/hnc/bin/stats_v52_gray_observe.sh text
HNC_V52_OBSERVE_SAMPLE=1 HNC_V52_OBSERVE_REFRESH=1 sh /data/local/hnc/bin/stats_v52_gray_observe.sh text
cat /data/local/hnc/run/stats_v52_gray_observe.md | head -120
'
```

## 版本

- version: `v5.2.0-rc1.17`
- versionCode: `520027`
