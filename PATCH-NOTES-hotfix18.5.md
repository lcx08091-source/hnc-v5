# HNC v5.1.0-rc1 hotfix18.5

## 目标

把 hotfix18.3/18.4 的 JSON 校验、备份、恢复能力纳入日常诊断与 debug 包，减少用户排障时需要手动 cat 多个文件的问题。

## 改动

- 新增 `bin/json_diag_bundle.sh`
  - 只读收集，不修改 live JSON。
  - 运行 `json_doctor.sh status/list`。
  - 对 `rules.json`、`device_names.json`、`templates.json`、`remote_tokens.json`、`devices.json` 执行 `json_guard.sh`。
  - 收集 `json_health.json/txt`、`tc_state.json`、`tc_state.*.txt`、`capabilities.*`。
  - 收集最近 JSON 备份列表和最近 20 个备份副本。
  - 收集 live JSON 与日志 tail，输出 `/sdcard/Download/hnc-json-debug-*.tar.gz`。

- 增强 `bin/diag.sh`
  - 新增 JSON 健康检查。
  - 新增 JSON 备份/TC 快照检查。

## 使用

```sh
su -c 'sh /data/local/hnc/bin/json_diag_bundle.sh'
```

生成后把 `/sdcard/Download/hnc-json-debug-*.tar.gz` 发给审查者即可。

## 风险

低。此版本只新增只读诊断入口和 diag 检查，不改变 JSON 写入逻辑、不改变 TC/iptables 规则。
