# HNC v5.1.0-rc1 hotfix22.4

## 目标

v5.2 stats RC 灰度前增加一键真实机检查入口，方便在小米10 / MIUI14、realme GT 7 Pro / ColorOS 等真实设备上判断是否可以进入 v5.2-rc1 灰度。

本补丁仍然不切换默认 stats，不启用 RC，不改限速/延迟/iptables/tc/watchdog 核心逻辑。

## 新增

- `bin/stats_v52_device_check.sh`
  - 只读聚合真实机状态。
  - 输出：
    - `/data/local/hnc/run/stats_v52_device_check.json`
    - `/data/local/hnc/run/stats_v52_device_check.txt`
  - 聚合：
    - `stats_v52_diag_bundle.sh`
    - `stats_health_summary.sh`
    - `stats_v52_rc_control.sh`
    - `stats_v52_rc_smoke.sh`
    - `stats_migration_readiness.sh`
    - `stats_compare.sh`
    - `stats_source_diag.sh`
    - `stats_shadow_diag.sh`
    - `stats_shadow_control.sh`
    - `stats_identity_diag.sh`
    - `stats_retention_diag.sh`
    - `stats_diag.sh`
  - 同时记录设备信息、模块版本、热点 iface、capabilities 摘要、legacy/shadow stats 行数和大小。

## 接入

- `bin/json_diag_bundle.sh`
  - 收集 `stats_v52_device_check` 的 JSON/TXT 输出。
  - manifest 增加 `has_stats_v52_device_check`。

- `bin/json_health_panel.sh`
  - 面板 JSON 增加 `v52_device_check_raw`。
  - 如果真实机检查 fail，则整体 health panel 置为 fail。
  - 如果真实机检查 warn，则整体 health panel 至少为 warn。

- `bin/ci_preflight.sh`
  - 必备文件/可执行检查加入 `bin/stats_v52_device_check.sh`。

## 用法

```sh
su -c 'sh /data/local/hnc/bin/stats_v52_device_check.sh text'
su -c 'sh /data/local/hnc/bin/stats_v52_device_check.sh json'
```

需要导出本机检查小包时：

```sh
su -c 'sh /data/local/hnc/bin/stats_v52_device_check.sh bundle'
```

## 预期解释

- `status=pass`：真实机检查通过，可继续 v5.2 RC 灰度观察。
- `status=warn`：通常代表 RC 仍关闭或 shadow stats 仍在 warmup，继续 legacy 默认并收集样本。
- `status=fail`：不要进入 v5.2 RC；如果 RC 已启用，应先 disable 并导出诊断包。

## 版本

- version: `v5.1.0-rc1-hotfix22.4`
- versionCode: `509224`
