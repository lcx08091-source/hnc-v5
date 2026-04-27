# HNC hotfix20.0

## 目标

继续 JSON 统一专项，但对 `remote_tokens.json` 保持谨慎：不接管 Go TokensStore 的签发、last_seen、atomic merge 逻辑，只把 shell 侧撤销写路径迁移到 `hnc_json`。

## 改动

- `bin/hnc_json` 新增：
  - `set-map-field <file> <top_key> <entry_key> <field> <value> [type]`
  - `token-revoke <file> <token_id>`
  - `token-revoke-all <file>`
- `bin/json_set.sh`：
  - `token_revoke` 优先走 `hnc_json token-revoke`
  - `token_revoke_all` 优先走 `hnc_json token-revoke-all`
  - 保留 legacy fallback
- 不修改 Go `TokensStore` 的 `PutIfAbsent` / `UpdateLastSeen` / `saveAtomicLocked` / `Prune` 语义。
- 新增回归测试：
  - `test/unit/test_json_set_tokens_hnc_json_bridge.sh`

## 验证重点

- 撤销单个 token 只应改目标 token 的 `revoked` 字段。
- 不存在的 TokenID 应保持幂等，不损坏 JSON。
- `token_revoke_all` 应撤销所有未撤销 token。
- label / ip_hint 中包含逗号、右花括号、引号、反斜杠、中文时不应写坏 JSON。
- 写完后 JSON guard 必须通过。

## 版本

- version: `v5.1.0-rc1-hotfix20.0`
- versionCode: `509200`
