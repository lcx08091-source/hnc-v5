# HNC v5.1.0-rc1-hotfix19.7

## 目标

继续 JSON 统一专项，把 `device_names.json` 的手动设备命名写路径迁移到 `hnc_json`，减少名称包含逗号、右花括号、引号、反斜杠、中文时写坏 JSON 的风险。

## 变更

- `bin/hnc_json`
  - 新增 `get-object-key <file> <key>`。
  - 新增 `set-object-key <file> <key> <value> [str|num|bool|null]`。
  - 新增 `del-object-key <file> <key>`。
  - `LOCKDIR` / `BACKUP_DIR` 支持跟随 `HNC` / `JSON_BACKUP_DIR` 环境变量，便于回归测试和临时目录验证。

- `bin/json_set.sh`
  - `name_set` 优先走 `hnc_json set-object-key`。
  - `name_get` 优先走 `hnc_json get-object-key`。
  - `name_del` 优先走 `hnc_json del-object-key`。
  - 保留 legacy fallback，不影响缺失 `hnc_json` 的异常环境。

- `test/unit/test_json_set_names_hnc_json_bridge.sh`
  - 覆盖名称包含逗号、右花括号、双引号、反斜杠、中文。
  - 覆盖删除存在/不存在的 name 后 JSON 仍然有效。

## 版本

- version: `v5.1.0-rc1-hotfix19.7`
- versionCode: `509197`
