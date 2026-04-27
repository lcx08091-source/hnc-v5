# HNC v5.1.0-rc1-hotfix20.9

## 目标

继续收窄 C 版 `hnc_json` 风险面，不改变运行时写入策略，重点补齐 CI / artifact 级别检查和诊断信息。

## 改动

- `ci_preflight.sh --artifact` 增强：
  - 检查编译产物内 `module.prop` 的 `version/versionCode` 是否与源码一致。
  - 如果产物包含 `bin/hnc_json_c`，检查 ELF machine 必须是 Android ARM/AArch64。
  - 如果没有 `hnc_json_c`，明确记录为可接受状态。
- `json_diag_bundle.sh` 增加收集：
  - `hnc_json_c_status.sh` 输出。
  - `hnc_json version` 输出。
- `json_health_panel.sh` 增加 `hnc_json_c.status_raw`，便于 WebUI/诊断页看到 C helper 是否存在、是否启用、写入是否仍为 opt-in。
- 新增回归测试：
  - `test/unit/test_ci_preflight_artifact_gate.sh`

## 安全边界

- 不启用 C helper 写入。
- 不删除 shell fallback。
- 不改变 `json_set.sh` / `json_set_batch.sh` 写入路径。
- 只加强检查和诊断。

版本：`v5.1.0-rc1-hotfix20.9`
versionCode：`509209`
