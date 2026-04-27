# HNC hotfix21.9 Patch Notes

## 目标

新增 stats 迁移就绪度门禁，用于 v5.2-rc1 之前判断 shadow stats 是否已经具备切换条件。

## 改动

- 新增 `bin/stats_migration_readiness.sh`
- `stats_health_summary.sh` 纳入 migration readiness 状态
- `json_diag_bundle.sh` 收集 migration readiness JSON/text
- `json_health_panel.sh` 输出 migration readiness 原始状态
- `ci_preflight.sh` 增加 helper 存在与权限检查
- 新增 `test/unit/test_stats_migration_readiness.sh`
- 版本升级到 `v5.1.0-rc1-hotfix21.9` / `versionCode=509219`

## 安全边界

- 不启用 shadow stats
- 不切换 WebUI 默认统计来源
- 不修改旧 stats 采样/rollup
- 不修改 TC / iptables / watchdog / JSON 写入主逻辑
