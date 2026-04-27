# HNC v5.1.0-rc1 hotfix20.7

## 目标

修正 hotfix20.5/20.6 引入的可选 C 版 `hnc_json` 桥接风险：防止把 Linux/x86_64 主机上编译出来的 `bin/hnc_json_c` 误打包进 Android 模块。

## 改动

- `bin/hnc_json` 增加 C helper ELF 架构门禁：
  - 默认只允许 Android ARM/AArch64 helper。
  - host/x86 helper 默认不会被调用。
  - 单元测试可用 `HNC_JSON_C_ALLOW_HOST=1` 显式放行。
- 删除源码树里误生成的 `bin/hnc_json_c` 预编译文件。
- `daemon/hotspotd/tools/build_hnc_json.sh` 默认拒绝 host/Linux 编译，必须使用 Android NDK clang；单元测试可显式设置 `HNC_JSON_C_ALLOW_HOST=1`。
- 新增 `bin/hnc_json_c_status.sh`，用于查看 C helper 是否存在、架构、是否会启用。
- `ci_preflight.sh` 增加 `bin/hnc_json_c` 架构检查，发现 host/x86 helper 时直接失败。
- 修复 `test_hnc_json_c_write_bridge.sh` 的 `/tmp` 硬编码，改用 `$TMPDIR` 或仓库 `.tmp`，并显式声明 host helper 仅用于单元测试。

## 不改动

- 不扩大 C 写入路径。
- 不删除 shell fallback。
- 不删除 legacy fallback。
- 不改 TC / iptables / watchdog / WebUI 主逻辑。
