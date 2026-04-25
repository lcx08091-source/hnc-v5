# HNC v5.1.0-rc1 hotfix10

## 目标

- 补齐 hotfix9 后端 B 部分: 长期离线规则自动清理,避免 rules.json 无限膨胀。
- 合入 round3 中优先级较高的 C3 / S5 / S11 / C1。
- 保持 busybox ash 兼容,不引入高风险队列或大改架构。

## 本轮改动

### P1 · stale rules 自动清理

- 新增 `bin/cleanup_stale_rules.sh`。
- 默认 `stale_rule_ttl_days=30`,设置为 `0` 可禁用自动清理。
- 只清理 `rules.json.devices[mac]` 中长期未见的限速/延迟规则记录。
- 不删除 `blacklist` / `whitelist` / `device_names.json`,避免误删用户明确配置。
- 当前仍在线的 MAC 永远跳过,避免 last_seen_persist 未及时刷新时误删。
- `service.sh` 启动后 60 秒跑一次清理。
- `watchdog.sh` 每天最多调度一次清理。

### last_seen_persist

- `apply_device_rule.sh limit` 成功路径写入 `last_seen_persist`。
- `apply_device_rule.sh alloc_mid` 写入 `last_seen_persist`,覆盖 delay-only 场景。
- 新增 `json_set.sh device_remove <mac>`,供 cleanup 删除设备规则整条记录。

### C3 · hotspotd rules.json 16KB 截断

- `daemon/hotspotd/hotspotd.c write_json()` 不再使用 `char buf[16384]` 读取 rules.json。
- 改为按文件大小 `malloc(size+1)` 动态读取,上限 1MB。
- 防止大 rules.json 下 blacklist 位于末尾时被截断,导致设备状态错误。

### S5 · ensure_stats 去重

- `bin/iptables_manager.sh ensure_stats()` 不再使用 `-C || -A`。
- 改为先删除同 IP 现存重复 RETURN 规则,再追加唯一一对 `-s/-d RETURN`。
- 避免并发 TOCTOU 导致统计规则重复、流量翻倍。

### S11 · service 启动 poll hotspotd.pid

- `service.sh` 中固定 `sleep 2` 改为最多 5 秒轮询 `hotspotd.pid`。
- 慢启动时不再过早误判 shell fallback,快启动时也不白等。

### C1 · find_device 大小写防御

- `daemon/hotspotd/hotspotd.c find_device()` 从 `strcmp` 改为 `strcasecmp`。
- 防御未来输入 MAC 大小写不一致导致重复设备条目。

## P0 说明

- `json_set_batch.sh` 的 IP 裸数字问题在 hotfix9 当前包中已经是严格数字判断,本轮没有重复改动。

## 更新日志位置

- `CHANGELOG.md`: 主更新日志。
- `PATCH-NOTES-hotfix10.md`: 本轮详细补丁说明。
- `webroot/changelog.html`: 本机 WebUI 里懒加载显示的变更记录。
- `module.prop`: 模块版本、versionCode 和模块管理器摘要。

## 需要重新编译

- 必须重新编译 `bin/hotspotd`,因为 C3/C1 修改了 `daemon/hotspotd/hotspotd.c`。
- 建议 GitHub Actions 同时重新编译 `bin/hnc_httpd` 和 `bin/hnc_tc_ingress`,保持产物一致。
- shell / WebUI 文件无需单独编译。

## 真机验收

```sh
su
H=/data/local/hnc

# 1. json_set device_remove smoke
sh $H/bin/json_set.sh device aa:bb:cc:dd:ee:ff mark_id 88
sh $H/bin/json_set.sh device_remove aa:bb:cc:dd:ee:ff
cat $H/data/rules.json | grep -i aa:bb:cc:dd:ee:ff && echo BUG || echo OK

# 2. stale cleanup smoke
sh $H/bin/json_set.sh device fa:ke:00:00:00:01 mark_id 99
sh $H/bin/json_set.sh device fa:ke:00:00:00:01 last_seen_persist 1
sh $H/bin/cleanup_stale_rules.sh
cat $H/data/rules.json | grep -i fa:ke:00:00:00:01 && echo BUG || echo OK

# 3. ensure_stats 去重
sh $H/bin/iptables_manager.sh ensure_stats 10.0.0.2
sh $H/bin/iptables_manager.sh ensure_stats 10.0.0.2
iptables -t mangle -S HNC_STATS | grep '10.0.0.2'

# 4. hotspotd 重编确认
strings $H/bin/hotspotd | grep -q 'rules.json too large' && echo hotspotd-hotfix10-present
```
