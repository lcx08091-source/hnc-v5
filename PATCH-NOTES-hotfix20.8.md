# HNC v5.1.0-rc1 hotfix20.8

## 目标

进一步降低 hotfix20.5/20.6 引入的可选 C 版 `hnc_json_c` 写路径风险。

## 改动

- `bin/hnc_json` 默认只允许 C helper 执行只读命令：
  - `validate`
  - `get-top` / `get`
  - `version`
- C helper 写命令默认禁用，必须显式设置：
  - `HNC_JSON_C_WRITE_ENABLE=1`
- 所有写入路径默认继续走 shell + `json_guard`：
  - `set-object-key`
  - `del-object-key`
  - `add-array-unique`
  - `del-array-value`
  - `token-revoke`
  - `token-revoke-all`
- `bin/hnc_json_c_status.sh` 增加：
  - `write_enabled`
  - `write_reason`
- 版本升级到：
  - `v5.1.0-rc1-hotfix20.8`
  - `versionCode=509208`

## 原则

这一步不删除 C helper，也不删除 legacy fallback，只是把 C 写路径改成显式实验开关，避免 CI 打包出 Android ARM helper 后运行时自动接管 JSON 写入。
