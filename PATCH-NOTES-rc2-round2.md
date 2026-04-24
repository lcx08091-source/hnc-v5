# HNC rc2 patch · Round 2 (12 项续修)

本轮继续 Round 1 之后, 按 Round 3 审查清单的 P1-P3 优先级处理. 10 个文件, 12 项修复.

**应用方式** (和 round 1 一样):
```sh
cd ~/hnc-v5
unzip -o /sdcard/Download/HNC-rc2-round2-patch.zip
git add -A && git diff --stat HEAD
git commit -m "rc2 round2: fix S7 S6 S8 S9 S10 S12 G5 G6 G8 G9 G10 G12"
git push
```

CI 重编 `hnc_httpd` binary, 下 artifact 装机.

---

## 改动清单

| 文件 | 改的 ID |
|---|---|
| `bin/iptables_manager.sh` | S7 (87 个 iptables/ip6tables 调用改用 `$IPT`/`$IP6T` 带 `-w 2`) |
| `bin/watchdog.sh` | S6 (`try_spawn_lock` helper), S10 (双 pid 缺兜底) |
| `bin/cleanup.sh` | S9 (`pkill -f` 模式收窄) |
| `bin/apply_device_rule.sh` | S12 (clear 路径不分配未用 mid) |
| `service.sh` | S8 (删 trap 死代码) |
| `daemon/hnc_httpd/action.go` | G6 (UTF-8 cut=0 fallback), G9 (runBinDetached defer recover) |
| `daemon/hnc_httpd/action_v5.go` | G12 (TokenID 注释纠正) |
| `daemon/hnc_httpd/api_v5.go` | G10 (tailFile 加 3s context 超时) |
| `daemon/hnc_httpd/pair.go` | G5 (logout 删多余 Flush) |
| `daemon/hnc_httpd/server.go` | G8 (serveIndex 加 sync.Once 缓存) |

---

## 逐项说明

### S7 · iptables 全局 `-w 2` xtables 锁
**文件**: `bin/iptables_manager.sh`
**问题**: 52+ 次 iptables/ip6tables 调用全部裸命令, 没有 `-w` lock wait. 当
watchdog + apply_device_rule 并发触发时 (真机常见, 用户边点 WebUI 边自愈), xtables
被占的瞬间 iptables 直接 EAGAIN 退出, 规则应用不完整, 静默失败.
**修法**: 顶部定义 `IPT="iptables -w 2"` / `IP6T="ip6tables -w 2"`, 全文件批量换成变量.
`-w 2` = 等最多 2 秒, 覆盖绝大多数瞬时竞争 (oplus_netd 也极少持锁 >1s).
**例外**: 第 89 行 `command -v ip6tables` 必须保留裸名 (command -v 只接受 1 个 arg).
**验证**:
```sh
grep -c '\$IPT\b' bin/iptables_manager.sh   # 应 ~65
grep -c '\$IP6T\b' bin/iptables_manager.sh  # 应 ~22
# 语义不变: 并发时多了 2s 锁等待, 非并发时无可观测差别.
su -c 'sh /data/local/hnc/bin/apply_device_rule.sh limit <MAC> 5 5'  # 应正常
```

### S6 · spawn_lock 陈旧检测
**文件**: `bin/watchdog.sh`
**问题**: `mkdir $RUN/daemon.spawn` 拿锁失败直接 skip 本轮. 若上次 watchdog 被
SIGKILL (OOM/用户 pkill) 时正持锁, 目录遗留, 新 watchdog 永远进不了, 所有 daemon
重启永久阻塞, 必须重装模块.
**修法**: 加 `try_spawn_lock` helper — mkdir 失败时看目录 mtime, 超过 60 秒视为陈旧,
强释放 + 重拿. 两处 mkdir 调用改用 helper.
**验证**:
```sh
su -c 'mkdir /data/local/hnc/run/daemon.spawn'
su -c 'touch -d "2 minutes ago" /data/local/hnc/run/daemon.spawn'
# 等 60 秒内 watchdog 下一轮, 应看到:
# WARN: spawn lock ... stale (>60s), forcibly releasing
su -c 'grep stale /data/local/hnc/logs/watchdog.log'
```

### S8 · 删 service.sh 死 trap
**文件**: `service.sh`
**问题**: `trap cleanup_on_exit TERM INT` 是 v3.x 遗留的死代码. Magisk/KSU 把
service.sh 以 daemonize 拉起, init 不发 TERM/INT (卸载走 uninstall.sh 钩子,
关机 init 发 KILL — trap 拦不到). 保留给读代码的人"有清理保证"的错觉.
**修法**: 删 trap + 函数体, 改成注释说明为什么.
**验证**: `grep trap service.sh` 应无输出.

### S9 · `pkill -f` 模式收窄
**文件**: `bin/cleanup.sh`
**问题**: 原来 `for proc in device_detect watchdog hotspot_autostart; pkill -f $proc`.
`pkill -f` 是 full cmdline 匹配, "watchdog" 会误杀 cmdline 里含 "watchdog" 任意字
样的进程 (用户在编辑器打开 watchdog.sh / 其他模块路径含 watchdog 等).
**修法**: 改用 `bin/watchdog.sh`, `bin/device_detect.sh`, `bin/hotspot_autostart.sh`
做模式, 把误杀面收窄到只会在 HNC 脚本路径里出现的字符串.
**验证**: `grep "bin/.*\.sh" bin/cleanup.sh` 能看到 3 个新模式.

### S10 · watchdog 双 pid 缺兜底
**文件**: `bin/watchdog.sh`
**问题**: `check_services` 逻辑是"先查 hotspotd.pid, 缺则查 detect.pid". 如果两个
都缺 (用户手动 pkill + rm pid 或者 post-fs-data 还没写 pid 时 watchdog 先跑),
函数 `return 0` 什么都不做. 真机事故: 用户清过一次 pid 后 watchdog 永远不恢复,
必须重启模块.
**修法**: 在 detect.pid 分支后加 `elif [ -z "$det_pid" ]` 兜底, 拉起 device_detect
daemon (自己会尝试起 C daemon 或回落 shell), 受 RESTART_COOLDOWN 保护.
**验证**:
```sh
su -c 'pkill -f hotspotd; rm -f /data/local/hnc/run/*.pid'
# 等 60-120 秒 (COOLDOWN), 看:
su -c 'grep bootstrapping /data/local/hnc/logs/watchdog.log'
# 期望: "both hotspotd.pid and detect.pid missing, bootstrapping detector"
```

### S12 · clear 不分配未用 mid
**文件**: `bin/apply_device_rule.sh`
**问题**: `clear` 路径调 `get_or_assign_mid`, 对从未限速过的设备会分配一个全新 mid
然后立刻丢弃. CONNMARK_MASK 只给 99 个 mid, 每次对未限速设备点"清除限速"都烧一个,
长期会枯竭.
**修法**: clear 路径先 `json_set.sh device_get mark_id` 看是否有 mid, 没有就走
no-mid 快路径 (只写 rules.json 状态清理, 不动 tc/iptables).
**验证**:
```sh
# 对一台从未限速过的设备点清除
su -c 'sh /data/local/hnc/bin/apply_device_rule.sh clear <MAC>'
# 应看到日志:
su -c 'grep "no existing mid, skipping tc" /data/local/hnc/logs/apply.log | tail'
# rules.json 里该设备 mark_id 应仍为空, 没有消耗
```

### G5 · logout 删多余 Flush
**文件**: `daemon/hnc_httpd/pair.go`
**问题**: `handleLogout` 调 `s.tokens.Put(...)` + `s.tokens.Flush()`. 但 `Put` 内部
(tokens.go:350) 已经调 `saveAtomicLocked` — 包含一次原子写 + fsync. 再 `Flush` 又
调一次 `saveAtomicLocked`. 单次 logout 要两次 fsync, 在慢盘上用户可见延迟.
**修法**: 删掉冗余的 `Flush` 调用.
**验证**: 功能不变. 登出仍然立即持久化 (靠 Put 的 fsync), 只是少一次.

### G6 · UTF-8 截断 cut=0 fallback
**文件**: `daemon/hnc_httpd/action.go`
**问题**: shell 输出超 1024 字节时, 代码往左退到 `utf8.RuneStart` 找合法边界.
极端病态输入 (前 1024 字节全是 continuation bytes, 实际几乎不可能) 会退到 `cut=0`,
结果 `s[:0]+"..." = "..."`, 用户看到纯 `...`, 诊断价值为零.
**修法**: `cut==0` 时改用 `strings.ToValidUTF8` 把无效序列替换成 U+FFFD, 硬切 1024,
保留可读前缀.
**验证**: 正常路径不变. 病态输入 (极罕见) 至少能看到前缀而不是纯 `...`.

### G8 · serveIndex 加 sync.Once 缓存
**文件**: `daemon/hnc_httpd/server.go`
**问题**: KSU loopback 请求每次 `os.ReadFile("/data/adb/modules/.../webroot/index.html")`
读 222 KB. 前端 2.5s 轮询压榨 I/O. 磁盘上的 index.html 在 httpd 生命周期内不变
(模块 reinstall 会重启 httpd).
**修法**: 加 `loadIndexDiskOnce()` — 用 `sync.Once` 首次读后缓存 `[]byte`, 后续
serveIndex 直接 `w.Write(data)`. 读不到磁盘版时仍 fallback 到 embed `indexHTML`.
**验证**:
```sh
# 装上后首次访问 http://127.0.0.1:8444/, 再刷 10 次
# httpd.log 应只有 1 次 "ReadFile" 痕迹 (如果加了 log 的话, 否则看 ktrace)
# 前端响应时间首轮 ~几 ms, 后续 <1ms
```

### G9 · runBinDetached defer recover
**文件**: `daemon/hnc_httpd/action.go`
**问题**: `runBinDetached` 尾部 `go func() { _ = cmd.Wait() }()` 没有 panic 保护.
Go runtime 的 `exec.Cmd` 在某些并发场景 (Linux 罕见但真实存在, 见 golang issue
#23019 类) state 竞态会 panic, 整个 httpd 进程崩溃. 代价: cleanup.sh 跑一半
httpd 就死, 再也没人把 rules.json 恢复, 用户规则全丢.
**修法**: 加 `defer recover() + log.Printf`, panic 仅记录不扩散.
**验证**: 功能不变. 极罕见的 panic 现在能在 httpd.log 看到而不是 crash.

### G10 · tailFile 加 3s context 超时
**文件**: `daemon/hnc_httpd/api_v5.go`
**问题**: `/api/logs` 调 `exec.Command("tail", "-n", ..., path).Output()` 没有
timeout. 如果磁盘卡 / fuse 挂起 / overlay 损坏, tail 子进程永久 hang, HTTP
goroutine 泄漏一个到重启.
**修法**: 用 `exec.CommandContext(ctx, ...)` + `context.WithTimeout(3s)`. 正常 tail
10 MB 日志远远用不到 3s.
**验证**: 正常路径无观测差异. 异常磁盘场景返回空字符串而不是挂死.

### G12 · TokenID 注释纠正
**文件**: `daemon/hnc_httpd/action_v5.go`
**问题**: 注释写 "TokenID 是 16 字节 hex = 32 字符", 但 `auth.go:5` 真实定义是
"TokenID: 8 字节 random base64url (~11 字符)". 代码行为正确 (上下界 8-256 够宽),
只是注释误导未来读者.
**修法**: 改注释, 引用 auth.go 为准.

---

## 没动的 (留给 round 3+)

- **C1/C2/C3**: hotspotd.c 的 MAC tolower、stats 缓存、blacklist buf — 需要 C 侧
  架构理解, 风险高
- **S3**: 多处单行 JSON 解析假设 — 架构债, 要先把 JSON 读写统一到 Go httpd 的
  本地 IPC (tech debt #6 in HANDOFF)
- **S5**: `ensure_stats` 的 TOCTOU — 需要 flock 或用 iptables-restore 原子化
- **S11**: service.sh `sleep 2` 的时序判 C daemon 接管 — 需要改成 poll 直到
  hotspotd.pid 就绪
- **O10-O14**: 性能优化, 不是 bug
- **N5**: 行为观察项, 不是 bug

## 本地验证已做

- `GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build` 编过
- `go vet` 干净
- 所有改过的 shell 文件 `busybox ash -n` 语法通过
- diff 核对: 10 个文件实际改动, 范围与 ID 清单一一对应

## 累计修复率 (两轮合计)

| 类别 | 本次前 | Round 1 修 | Round 2 修 | 剩余 |
|---|---|---|---|---|
| P0 (B/G1/G3/N1) | 4 | **4** | — | 0 |
| P1 (G7/G11/S7/N2) | 4 | 3 | 1 (S7) | 0 |
| P2 (G4-G8/S4-S5/C3) | ~10 | 3 (G4 G7 S4) | 3 (G5 G6 G8) | ~4 |
| P3 (卫生/O) | ~15 | 3 (S2 N3 N4) | 7 (S6 S8 S9 S10 S12 G9 G10 G12) | ~5 |
| 总 | ~45 | 13 | 11 | ~14 |

---

*round 2 patch set 由 Claude (Anthropic) 生成, 2026-04-24, 基于已应用 round 1 的源码状态.*
