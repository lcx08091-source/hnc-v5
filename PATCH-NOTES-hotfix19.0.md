# HNC v5.1.0-rc1 hotfix19.0

## 目标

JSON 统一专项进入第二阶段：让 `bin/hnc_json set-top` 具备独立、安全的 top-level 写入能力。

## 改动

- `bin/hnc_json` 不再把 `set-top` 委托回 `json_set.sh`，避免后续迁移 `json_set.sh top -> hnc_json` 时产生递归。
- `set-top` 使用字符级扫描 top-level JSON object：识别字符串、转义、嵌套对象/数组。
- 写入前校验 live JSON，写入候选文件后再次校验。
- 写入前自动备份到 `/data/local/hnc/data/.json_backups`。
- 支持 `str/num/bool/null` 字面量类型。
- 新增 `test/unit/test_hnc_json_set_top.sh`，覆盖逗号、右花括号、引号、反斜杠、中文、bool/num/null。

## 风险控制

本 hotfix 只增强 `hnc_json` 自身，不强制替换运行时 `json_set.sh top`。下一步 hotfix19.1 再把 `json_set.sh top` 接到 `hnc_json set-top`，并保留 fallback。
