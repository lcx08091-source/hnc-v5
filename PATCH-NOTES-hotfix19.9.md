# HNC hotfix19.9

## 目标

继续 JSON 统一专项，把 `rules.json` 里的 blacklist 数组写入路径迁移到 `hnc_json`。

## 改动

- `bin/hnc_json` 新增：
  - `add-array-unique <file> <key> <value>`
  - `del-array-value <file> <key> <value>`
- `bin/json_set.sh`：
  - `bl_add` 优先走 `hnc_json add-array-unique`
  - `bl_del` 优先走 `hnc_json del-array-value`
  - 保留 legacy fallback
- 新增回归测试：
  - `test/unit/test_json_set_blacklist_hnc_json_bridge.sh`

## 验证重点

- 重复添加同一 MAC 不应重复写入。
- 删除不存在的 MAC 不应损坏 JSON。
- blacklist 修改不应影响 whitelist 或 devices。
- 写完后 JSON guard 必须通过。

## 版本

- version: `v5.1.0-rc1-hotfix19.9`
- versionCode: `509199`
