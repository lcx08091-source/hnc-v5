# HNC v5.1.0-rc1 hotfix1

本补丁基于用户上传的 `HNC-v5_1_0-rc1-arm64.zip` 修改，目标是修复代码审查中确认的关键“假成功 / 状态不一致 / 误删规则”问题，尽量不改架构和 UI。

## 运行时已生效的 Shell 修复

1. `bin/apply_device_rule.sh`
   - `clear` 不再无条件调用 `tc_manager.sh remove`。
   - 如果设备仍启用 `delay_enabled` / `delay_ms` / `jitter_ms` / `loss_pct`，只调用 `tc_manager.sh set_limit <iface> <mid> 0 0 <ip>` 清除限速 rate，保留 netem、tc class、iptables mark 和 offload disable 状态。
   - `mark_id` 分配范围修正为完整 `1..99`。
   - `mark_id` 全部占满时返回错误，不再回退复用已有 ID。

2. `bin/tc_manager.sh`
   - `ensure_device_class`、`set_limit`、`set_delay`、`set_all` 关键路径开始检查失败并返回非 0。
   - 修复 `set_all` 中 `set_limit` 失败但后续 `set_delay` 覆盖返回码的问题。
   - `fw filter` 添加失败会记录错误；如果没有 IP/u32 filter 兜底，会返回失败。

3. `bin/iptables_manager.sh`
   - 删除旧 mark / blacklist 规则时循环 `-D` 直到不存在，避免历史重复规则残留。

## 源码级修复，需重编预编译二进制后才会在真机运行时生效

> 注意：本环境没有 Android NDK 和 Go 1.25 依赖缓存，所以没有重编 `bin/hotspotd` 与 `daemon/hnc_httpd/hnc_httpd`。以下 C/Go 修复已经写入源码，但 ZIP 内的现有 ARM64 预编译二进制仍是原版。

4. `daemon/hotspotd/scheduler.c`
   - 修复 `rebuild_from_rules()` 对 `limit_enabled` 的误判。
   - 旧逻辑只要 block 内出现 `limit_enabled` 且任意字段为 `true`，就会把 `limit_enabled:false + delay_enabled:true` 误判为限速设备。
   - 新逻辑精确匹配 `"limit_enabled": true`。

5. `daemon/hotspotd/offload/adapter_bpf.c`
   - 为 BPF adapter 全局状态 `s` 增加 `pthread_mutex_t` 保护。
   - 修复 `disable_global` / `restore_global` 遍历 BPF map 时，`get_next_key` 遇到非 `ENOENT` 错误却可能返回 OK 的问题。

6. `daemon/hnc_httpd/action_v5.go`
   - `delay_set` 调用 `tc_manager.sh set_delay` 时增加当前设备 IP 参数，便于 delay-only 场景创建 ifb0 u32 src filter。

## 本地校验

- 已通过 `bash -n` 检查：
  - `bin/apply_device_rule.sh`
  - `bin/tc_manager.sh`
  - `bin/iptables_manager.sh`
- 已通过本地 `gcc -fsyntax-only` 检查：
  - `daemon/hotspotd/scheduler.c`
  - `daemon/hotspotd/offload/adapter_bpf.c`
- 未完成 Android ARM64 二进制重编译：缺少 Android NDK 与 Go 1.25/依赖缓存。

## 建议后续

如果要让 C/Go 修复在真机运行时生效，请在有 Android NDK 与 Go 1.25 依赖的环境中重编：

```sh
cd daemon/hotspotd
bash build.sh arm64

cd ../hnc_httpd
bash build.sh
```

然后确认新的：

- `bin/hotspotd`
- `bin/hnc_ipc`
- `daemon/hnc_httpd/hnc_httpd`

已经被复制进最终模块 ZIP。
