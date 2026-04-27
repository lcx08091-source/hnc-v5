# HNC hotfix19.8

## 目标

继续 JSON 统一专项，把 `templates.json` 的模板写入/删除路径迁移到 `hnc_json`。

## 改动

- `hnc_json` 的 `set-object-key` 支持 `json/raw` 类型。
  - 用于写入已经构造好的 JSON 对象值。
  - 写入前会先把 JSON fragment 作为候选 JSON 校验。
- `json_set.sh tpl_set` 优先调用：
  - `hnc_json set-object-key <templates.json> <template_name> <template_object> json`
- `json_set.sh tpl_del` 优先调用：
  - `hnc_json del-object-key <templates.json> <template_name>`
- 保留 legacy fallback：
  - `json_object_set_safe_file`
  - `json_object_del_safe_file`
- 新增回归测试：
  - `test/unit/test_json_set_templates_hnc_json_bridge.sh`

## 测试覆盖

- 模板名包含逗号。
- 模板名包含右花括号。
- 模板名包含双引号。
- 模板名包含反斜杠。
- 模板名包含中文。
- 模板字段仍保持数字对象，不被写成字符串。
- 删除不存在模板不损坏 JSON。
- 写完后 `hnc_json validate` 必须通过。

## 版本

- version: `v5.1.0-rc1-hotfix19.8`
- versionCode: `509198`
