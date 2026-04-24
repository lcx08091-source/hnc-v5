# HNC v5.1.0-rc1 hotfix2

基于 hotfix1 继续做最小风险修复。本包确认包含 hotfix1 的修改。

## 本轮新增修复

1. `bin/apply_device_rule.sh`
   - 修复 `bl_add` / `bl_del` 忽略 `json_set.sh bl_add/bl_del` 失败的问题。
   - 现在 iptables 已经应用但 JSON 持久化失败时，会输出 `ok partial_json_fail=blacklist_add|blacklist_del` 并写日志。
   - 目的：避免黑名单当前生效、重启后丢失，或者 UI/持久化状态和内核规则不一致。

2. `daemon/hotspotd/hotspotd.c`
   - 新增 `send_all()`，修复 IPC `send()` 短写导致 `GET_DEVICES` 或 offload/status JSON 返回半截内容的问题。
   - 所有 `handle_client()` 内的响应统一改为 `send_all()`。
   - 修复 `try_ns_dhcp_resolve()` 中 `malloc(BUF_CAP)` 失败时直接 `waitpid()` 可能卡住的问题；现在会先 `SIGKILL` dumpsys 子进程再收割。
   - 修复 crash handler 注释与实现不一致的问题：移除 signal handler 内的 `snprintf()` / `fsync()`，只用固定 `write()` 信息后 re-raise，降低崩溃时二次卡死风险。

3. `module.prop`
   - 版本号更新为 `v5.1.0-rc1-hotfix2`，`versionCode=50902`。

## 仍需注意

- Shell 修复安装后直接生效。
- C/Go 源码修复需要重新编译对应二进制才会进入运行时：
  - `bin/hotspotd`
  - `daemon/hnc_httpd/hnc_httpd`
  - 如涉及 tc netlink，也要重编 `bin/hnc_tc_ingress`。
- 本环境没有 Android NDK/Go 1.25，因此未重新生成 Android 目标二进制。

## 本地检查

- `bash -n bin/apply_device_rule.sh bin/tc_manager.sh bin/iptables_manager.sh bin/watchdog.sh bin/json_set.sh` 通过。
- 使用宿主机 `gcc -fsyntax-only` 对 `daemon/hotspotd/*.c` 和 `daemon/hotspotd/offload/adapter_bpf.c` 做语法检查通过。
- `gofmt` 已运行在 `daemon/hnc_httpd` 相关修改文件上。
