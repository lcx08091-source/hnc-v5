# HNC rc2 patch · Round 3 bug fix set

**作用方式**: 这是**源码 patch**, 不是可安装模块 zip.
解到你 repo 根目录覆盖, `git add -A && git commit && git push`,
等 GitHub Actions 出新 artifact, 下载装机测.

直接装这个 zip **不会生效大部分修复** — Go 改动需要 CI 重编 `hnc_httpd` 二进制.

---

## 应用方式

```sh
cd ~/hnc-v5
unzip -o /sdcard/Download/HNC-rc2-patch.zip
# 手工删 3 个 .bak (zip 没法携带 "删除" 语义)
rm -f bin/watchdog.sh.bak daemon/hnc_httpd/action.go.bak daemon/hnc_httpd/action_v5.go.bak
git add -A
git diff --stat HEAD   # 核对改动范围
git commit -m "rc2: fix B4 G1 G3 G4 G7 G11 S2 S4 N1 N2 N3 N4"
git push
```

## 改动文件 (9 个)

| 文件 | 修的 ID |
|---|---|
| `COMPATIBILITY.md` | N1 |
| `uninstall.sh` | N3 |
| `bin/watchdog.sh` | S2, S4 |
| `bin/apply_device_rule.sh` | G3 (加 alloc_mid 子命令) |
| `daemon/hnc_httpd/action.go` | G1, G4, G7 |
| `daemon/hnc_httpd/action_v5.go` | G3 (调 alloc_mid) |
| `daemon/hnc_httpd/main.go` | G11 |
| `daemon/hnc_httpd/pair.go` | G7 |
| `daemon/hnc_httpd/build.sh` | N4 |
| `daemon/hotspotd/lsm/hnc_lsm_loader.c` | B4 |

## 删除文件 (N2)

- `bin/watchdog.sh.bak`
- `daemon/hnc_httpd/action.go.bak`
- `daemon/hnc_httpd/action_v5.go.bak`

---

## 逐项说明 + 真机验证方法

### B4 · LSM loader 不再因 BPF LSM 缺失堵死 kprobe 路径
**文件**: `daemon/hotspotd/lsm/hnc_lsm_loader.c`
**改法**: Step 1 的 `probe_bpf_lsm_active() != 1 → return -2` 降级为**只打日志**.
kprobe 依赖 `CONFIG_KPROBES` (ColorOS 保留), 不需要 BPF LSM 在
`/sys/kernel/security/lsm` 里出现. 真正的 attach 失败由 Step 7 报告.

**验证**:
```sh
# 看 hotspotd 启动日志 step1 不再 fail
su -c 'grep "step1" /data/local/hnc/logs/hotspotd.log | tail'
# 期望看到: "BPF LSM NOT listed ...; Plan B uses kprobe, continuing to Step 7"
# 然后 Step 7 要么 "kprobe attached to security_bpf" (成功), 要么
# "attach_kprobe: <errno>" (这时才真是内核不支持 kprobe, 罕见)

# 看 guard 实际在拦
su -c 'grep -c COUNTER-WRITE /data/local/hnc/logs/hotspotd.log'
# 长时间跑应该 > 0 (framework 尝试 offload 时触发)
```

### G1 · 三重 switch 真删(rc5.1.1 只合了注释)
**文件**: `daemon/hnc_httpd/action.go` 228 附近
**改法**: 三个一模一样的 `switch action { case "pair_revoke"... }` 合成一个.
保留注释 "rc2 修 G1".

**验证**:
```sh
grep -c 'pair_revoke", "auth_required_set"' daemon/hnc_httpd/action.go
# 期望: 1
```

### G3 · delay_set 不再借 limit 0 0 路径污染状态
**文件**: `bin/apply_device_rule.sh` + `daemon/hnc_httpd/action_v5.go`
**改法**:
- 在 `apply_device_rule.sh` 加 `alloc_mid <mac>` 子命令, 只分配 mark_id +
  iptables mark + 写 `rules.json` 的 `mark_id` 字段. **不触 tc, 不写
  `limit_enabled/down_mbps/up_mbps`**.
- `actionDelaySet` 发现 device 没 mid 时改调 `alloc_mid`, 不再 `limit 0 0`.
- alloc_mid stdout 只出整数 mid, 供 Go 侧 `strconv.Itoa` / `intRE` 解析.
- 幂等: 重复调 alloc_mid 安全 (`get_or_assign_mid` 第一分支直接返回旧 mid,
  iptables `mark_device` 自带 -D 后 -A 清理).

**验证**:
```sh
# 对一台没有限速的设备加 50ms 延迟
su -c 'sh /data/local/hnc/bin/apply_device_rule.sh alloc_mid <MAC>'
# stdout 应输出一个整数
su -c 'grep <MAC> /data/local/hnc/data/rules.json'
# 期望: "limit_enabled" 不存在或为 false, mark_id 有值
# 以前会看到 "limit_enabled":true, "down_mbps":0, "up_mbps":0 (bug)
```

### G4 · mbit 换算从 1024 改 1000
**文件**: `daemon/hnc_httpd/action.go` 540 附近
**改法**: `kbit = num * 1024` → `kbit = num * 1000`.
tc 的 k/m 后缀是十进制 (iproute2 约定), 本文件 line 382 的
`mbit*1000 = kbit` 转换也是十进制, 统一.

**验证**:
设 5 mbit, 在设备上看 `tc class show dev ifb0` 的 rate 应显示 `5Mbit` 而不是 `5.12Mbit`.

### G7 · MaxBytesReader 防止大 body 耗内存
**文件**: `daemon/hnc_httpd/pair.go` 149 + `daemon/hnc_httpd/action.go` 177
**改法**: `ParseForm` 前 `http.MaxBytesReader(w, r.Body, 4096)` (pair: 4KB);
`json.NewDecoder` 前 `http.MaxBytesReader(w, r.Body, 16384)` (action: 16KB).

**验证**: 功能行为不变. 攻击者发 >16KB 的 POST body 会被 413 拒绝.

### G11 · ipOnly 用 net.SplitHostPort (IPv6 安全)
**文件**: `daemon/hnc_httpd/main.go` 287
**改法**: 原来 `strings.LastIndex(":")` 把 `[::1]:43210` 截成 `[::1` (错).
现在用 `net.SplitHostPort` 规范解析. 同文件移除不再使用的 `"strings"` import.

**验证**:
```sh
# 本地 loopback curl (IPv6)
su -c 'curl -sk https://[::1]:8443/healthz'
# 看 httpd.log 的 remote IP 字段应为 "::1" 而不是 "[::1"
```

### S2 · ensure_tc_uplink_healthy 真用 get_iface (不是假的 ${IFACE:-wlan2})
**文件**: `bin/watchdog.sh` 586 附近
**改法**: rc5.1.1 写了 `${IFACE:-wlan2}` 看起来有 fallback, 但 `IFACE` 在全
watchdog.sh 里从未赋值, 永远走到 `wlan2`. 现在调 `get_iface()` (line 87 起
的 5 分钟缓存), 失败才 fallback 到 `wlan2`.

**验证**:
```sh
# 如果你设备某天探到的热点 iface 变成 wlan0 / ap0, watchdog 也会跟上
su -c 'grep ensure_tc_uplink /data/local/hnc/logs/watchdog.log | tail'
```

### S4 · watchdog ACTIVE 分支热点关着时不再跳过 heartbeat
**文件**: `bin/watchdog.sh` 682 附近
**改法**: `probe_rc != 0` (热点临时关) 的 `continue` 之前先跑
`check_services / heartbeat / rotate_logs_periodic`, 避免用户关热点一会儿
watchdog 看着像挂了 + 日志不轮转 + 子服务不兜.

**验证**:
关热点, 等 3 分钟, 看 `watchdog.log`:
```sh
su -c 'tail /data/local/hnc/logs/watchdog.log'
# 应该每 60s 还有 heartbeat 打点 (之前会静默)
```

### N1 · COMPATIBILITY.md 降级 "✅ kprobe" 为 "❓ kprobe 未证实"
**文件**: `COMPATIBILITY.md` line 15
**改法**: 承认 kprobe attach 实际状态没有确凿测过. 说明"主路径不依赖 guard,
guard 只在 framework BPF offload 触发时起作用".
**这一项可以在 B4 真机验证后直接改回 ✅.**

### N3 · uninstall.sh 备 tokens.json
**文件**: `uninstall.sh` line 13 附近
**改法**: 和 rules.json / device_names.json 一起备, 让重装后已配对 token 不丢.

### N4 · build.sh 读不到 version 直接失败
**文件**: `daemon/hnc_httpd/build.sh`
**改法**: `VERSION=""` 时 `exit 1` 并打错误消息, 不静默注入 "dev".
防止 CI 跑在错 cwd 下默默构建出版本号是 "dev" 的 binary.

---

## 没动的 ID (留给下一轮或你决定)

- **S7** iptables 全局 `-w`: 52 个调用点, 机械可做但范围广, 单起一轮
- **C1-C3**: hotspotd.c 的 MAC 大小写 / stats 缓存 / blacklist buf. 需要 C 侧理解
- **S3 / S5 / S6 / S8-S12**: 各种小 shell 风险. 单个低, 合起来打包
- **G5 / G6 / G8-G10 / G12**: Go 侧 minor. 不影响功能
- **O10-O14**: 性能优化
- **N5**: 观察项, 不是 bug

## 本轮改动量

```
9 files changed, ~130 lines touched
  shell: 3 files
  Go:    4 files
  C:     1 file
  MD:    1 file
```

Go 编译 (`GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build`) 本地验证通过.
Shell 脚本 `busybox ash -n` 语法通过.
C 侧无本地工具链, 只做了人工 diff 核对 (B4 变动不涉及新头文件/新 API).

---

*patch set 由 Claude (Anthropic) 生成, 2026-04-24, 基于 rc5.1.1 源码 + Round 3 审查清单.*
