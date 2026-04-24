#!/system/bin/sh
# service.sh — Magisk late_start service
# 在系统完全启动后执行,可访问所有系统服务

# v3.5.0 alpha-0:PATH 健壮性
# 强制使用系统 PATH,排除 user app(MT 管理器/termux 等)对 awk/sed/grep/tc 的劫持
# 之前的隐患:如果 user 在 root shell 中调用 service.sh,继承的 PATH 可能含 user app 路径,
# 导致 HNC 用错版本的命令(行为可能跟系统 toybox 不一致)
[ -z "$HNC_SKIP_PATH_HARDENING" ] && [ -z "$HNC_TEST_MODE" ] && export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH

MODDIR=${0%/*}
HNC_DIR=/data/local/hnc
LOG=$HNC_DIR/logs/service.log
RUN=$HNC_DIR/run

mkdir -p $HNC_DIR/logs $RUN

# rc3.1 修 N-15R: 记下自己路径让 cleanup.sh restart 时能找到我们
# (KSU / SukiSU / Magisk 的 MODDIR 路径不一样, 不能硬编码)
echo "$MODDIR" > "$RUN/service.path" 2>/dev/null

# rc2 修 S8: 删除死 trap.
# 原有 trap cleanup_on_exit TERM INT + cleanup_on_exit() 函数是死代码:
# Magisk/KSU 的 post-fs-data/service 脚本是被 init 以 daemonize 方式拉起, init 不会
# 给 service.sh 发 TERM/INT (模块卸载走 uninstall.sh 钩子, 系统关机 init 发 KILL).
# 这段保留了几年没起过作用, 还给读代码的人"有清理保证"的错觉. 真清理在
# cleanup.sh 和 uninstall.sh, 不在这里.

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HNC] $1" >> $LOG
}

log "=== HNC Service Starting ==="
log "Android $(getprop ro.build.version.release) / $(getprop ro.product.brand) $(getprop ro.product.model)"

# 等待系统网络服务就绪
wait_for_network() {
    local max=60
    local cnt=0
    while [ $cnt -lt $max ]; do
        # 检查 wlan0 或热点接口
        if ip link show 2>/dev/null | grep -qE 'wlan|ap0|swlan'; then
            log "Network interface ready"
            return 0
        fi
        sleep 2
        cnt=$((cnt+2))
    done
    log "WARN: Network wait timeout, continuing anyway"
    return 1
}

# 等待 bootcomplete
wait_boot_complete() {
    local cnt=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ $cnt -lt 120 ]; do
        sleep 2
        cnt=$((cnt+2))
    done
    log "Boot completed at ${cnt}s"
}

wait_boot_complete
wait_for_network

# ─── v4.0.0-patch1.5 Defer Init(延迟初始化)────────────────────
# 历史(v4.0.0-patch1.4 及更早):
#   service.sh 跑在 late_start(~boot 5s), 此时热点通常还没起,
#   detect_hotspot_iface 的探测链层层失败最终兜底 echo "wlan0",
#   然后 tc_manager.sh init wlan0 + iptables_manager.sh init
#   直接把 HTB 队列和 MARK 规则挂到了本机 WiFi 接口 wlan0,
#   污染手机自己的上网体验(用户真机事故: 感觉"上网慢",
#   tc qdisc show dev wlan0 发现 HTB 活着几个月,但无人察觉)。
#
# v4.0.0-patch1.5 修正:
#   service.sh 彻底剥离业务初始化,不再探测 iface / 不再 init tc /
#   不再 init iptables / 不再直接拉 httpd。只做三件事:
#     1. 建目录 / 初始化 data 文件(已有逻辑,不变)
#     2. 启动 device_detect daemon
#     3. 启动 watchdog(它是唯一的状态机,负责探测 + init + 拉 httpd)
#   如果 remote_enabled=true, 写 httpd.wanted marker, watchdog 探到热点
#   就绪后自己拉 httpd。service.sh 绝不碰 wlan0。

log "v4.0.0-patch1.5 Defer Init: iface detection + tc/iptables init delegated to watchdog"

# v5.0: httpd 永远启动 (至少 loopback), 本机 WebUI 依赖它
# REMOTE_ENABLED 只决定是否同时开热点段 HTTPS
REMOTE_ENABLED=$(grep -o '"remote_enabled"[[:space:]]*:[[:space:]]*[a-z]*' \
    $HNC_DIR/data/rules.json 2>/dev/null | awk -F: '{print $2}' | tr -d ' ')
if [ "$REMOTE_ENABLED" = "true" ]; then
    log "remote_enabled=true, httpd.wanted marker set (watchdog will launch httpd with remote+loopback when hotspot ready)"
else
    log "remote_enabled=false, httpd loopback-only mode (本机 WebUI 仍可用)"
fi
# marker 总是 set — watchdog 看 remote_enabled 再决定是否带 -bind
touch "$RUN/httpd.wanted" 2>/dev/null

# 验证 hnc_httpd binary 存在且可执行(防御性 chmod,zip 安装可能丢 +x)
HTTPD_BIN="$HNC_DIR/daemon/hnc_httpd/hnc_httpd"
if [ -f "$HTTPD_BIN" ] && [ ! -x "$HTTPD_BIN" ]; then
    chmod 755 "$HTTPD_BIN" 2>/dev/null
    log "fixed +x on $HTTPD_BIN"
fi
if [ ! -x "$HTTPD_BIN" ]; then
    log "WARN: $HTTPD_BIN missing or not executable — WebUI 将不可用"
    log "      check that post-fs-data.sh copied daemon/hnc_httpd/hnc_httpd"
fi

# ─── 启动设备检测守护进程（v3.0.0：优先 C daemon hotspotd）─
# device_detect.sh daemon 内部会优先尝试启动 hotspotd(C)；
# 若二进制不存在则自动回落到原 shell 轮询（向下兼容）
#
# v3.5.2 P0-A 修复:detect.pid 和 hotspotd.pid 不再存同一个 PID。
# - C daemon 成功接管时,只有 hotspotd.pid 有值,detect.pid 不写
# - shell fallback 时,只有 detect.pid 有值(device_detect.sh 自己写)
# - watchdog 优先检查 hotspotd.pid,存在时跳过 detect.pid 检查
# 根本原因:之前两个 pid 指同一 PID,hotspotd 崩掉后 watchdog 两个
# if 都触发重启,导致 hotspotd C daemon 和 shell fallback 同时运行,
# 并发写 devices.json.tmp → JSON 损坏(review P0-A)
log "Starting device detector (C daemon preferred)..."
sh $HNC_DIR/bin/device_detect.sh daemon >> $HNC_DIR/logs/detect.log 2>&1 &
DETECT_SHELL_PID=$!
sleep 2
# 检查 C daemon 是否接管了（hotspotd.pid 存在且进程活着）
HPID=$(cat $RUN/hotspotd.pid 2>/dev/null)
if [ -n "$HPID" ] && kill -0 "$HPID" 2>/dev/null; then
    log "C daemon hotspotd running (PID=$HPID)"
    # v3.5.2 P0-A:不再 echo $HPID > detect.pid。
    # C daemon 模式下 detect.pid 应当不存在,让 watchdog 看到"没 detect 需要照料"
    rm -f "$RUN/detect.pid" 2>/dev/null
else
    # shell fallback 在 daemon_shell_fallback 里自己写了 detect.pid
    log "Shell daemon fallback running (PID=$DETECT_SHELL_PID)"
fi

# ─── 启动 Watchdog ──────────────────────────────────────────
log "Starting watchdog..."
sh $HNC_DIR/bin/watchdog.sh >> $HNC_DIR/logs/watchdog.log 2>&1 &
echo $! > $RUN/watchdog.pid

log "=== All services started ==="
log "All services started. WebUI: open KernelSU manager → modules → HNC"

# ─── v5.0 alpha.2: Offload Recovery ────────────────────────
# hotspotd 重启后 scheduler 内存里 limited 集合是空的, 但 rules.json 里
# 可能有 limit_enabled=true 的设备. 重新通知 scheduler 建立集合,
# 这样下一次 apply_device_rule.sh 或 watchdog 触发时状态一致.
#
# 后台异步跑, 不阻塞 service.sh. hotspotd 刚启动需要 2s 让 unix socket 就绪.
(
    sleep 3
    RULES="$HNC_DIR/data/rules.json"
    HNC_IPC="$HNC_DIR/bin/hnc_ipc"
    [ -f "$RULES" ] && [ -x "$HNC_IPC" ] || exit 0

    # 扫 rules.json 里所有 "limit_enabled":true 的 mac
    # 格式假设: {"aa:bb:...":{..."limit_enabled":true...},...}
    # 用 grep 非贪婪粗暴匹配, 不引入 jq 依赖 (ColorOS 不装)
    RECOVERED=0
    for MAC in $(grep -oE '"[0-9a-fA-F:]{17}"[^}]*"limit_enabled"[[:space:]]*:[[:space:]]*true' "$RULES" \
                 | grep -oE '^"[0-9a-fA-F:]{17}"' \
                 | tr -d '"'); do
        "$HNC_IPC" OFFLOAD_NOTIFY_LIMIT "$MAC" 1 >/dev/null 2>&1 && RECOVERED=$((RECOVERED+1))
    done
    if [ "$RECOVERED" -gt 0 ]; then
        log "offload recovery: notified $RECOVERED limited device(s) to scheduler"
    fi
) &

# ─── 热点自动启动 ────────────────────────────────────────────
# 读取 rules.json 里的 hotspot_auto 字段（WebUI 控制）
HOTSPOT_AUTO=$(grep -o '"hotspot_auto"[[:space:]]*:[[:space:]]*[a-z]*' \
    $HNC_DIR/data/rules.json 2>/dev/null | awk -F: '{print $2}' | tr -d ' ')

if [ "$HOTSPOT_AUTO" = "true" ]; then
    log "hotspot_auto=true, launching hotspot_autostart.sh in background..."
    # 延迟 5 秒再启动，确保其他网络服务就绪
    (sleep 5 && sh $HNC_DIR/bin/hotspot_autostart.sh start) \
        >> $HNC_DIR/logs/hotspot.log 2>&1 &
    echo $! > $RUN/hotspot.pid
    log "Hotspot autostart scheduled (PID: $(cat $RUN/hotspot.pid))"
else
    log "hotspot_auto=false, skipping autostart"
fi
