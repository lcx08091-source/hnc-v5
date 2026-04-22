# HNC v5.0 alpha.1 集成指南

把第三批 (累积) zip 解到 `~/hnc/` 之后, 这份文档告诉你需要 patch 哪些
**现有 v4.1 文件**才能把 scheduler 接到 hotspotd 主循环 + 让
`apply_device_rule.sh` 在限速生效/解除时通知 scheduler。

---

## 0. 改动总览

| 类别 | 内容 | 行数 |
|---|---|---|
| 新增源文件 | `daemon/hotspotd/platform.{h,c}` `scheduler.{h,c}` `offload/*` | 1683 |
| 新增工具 | `daemon/hotspotd/tools/{platform_probe,offload_ctl,sched_test,hnc_ipc}.c` | 720 |
| Patch `daemon/hotspotd/hotspotd.c` | 4 处, 共 ~30 行 | — |
| Patch `daemon/hotspotd/build.sh` | 加 5 个 .c 进 SRCS + `-DHNC_HAVE_ADAPTER_BPF` | 3 行 |
| Patch `bin/apply_device_rule.sh` | 2 处 notify, 1 个 helper 函数 | ~20 行 |
| Patch `service.sh` | 装 `bin/hnc_ipc` 二进制 (build 阶段) | 0 行 (build 改) |

**风险等级**: 中。所有 patch 都在 `null adapter` 兜底下安全。
即使 `adapter_bpf` 在某些 ROM 上行为异常, scheduler 也能回落 null,
hotspotd 主流程 100% 不受影响。

---

## 1. 编译

### 1.1 主 daemon 加上新源文件

编辑 `daemon/hotspotd/build.sh`, 把 `SRCS=...` 一行替换为:

```sh
# v5.0: 加入 platform / scheduler / offload adapter 抽象层
SRCS="hotspotd.c hnc_helpers.c hostname_cache.c oui_override.c mdns_worker.c \
      platform.c scheduler.c \
      offload/adapter.c offload/adapter_null.c offload/adapter_bpf.c"
```

并在编译命令的 `-D_GNU_SOURCE -DANDROID` 之后追加:

```sh
    -DHNC_HAVE_ADAPTER_BPF \
```

(通过 `g_adapters[]` 的 `#ifdef` 控制是否纳入 bpf adapter, alpha.1
默认开)

### 1.2 工具编译

```sh
cd daemon/hotspotd/tools
bash build.sh arm64           # 编 4 个工具
ls prebuilt/arm64/
# platform_probe  offload_ctl  sched_test  hnc_ipc
```

### 1.3 把 `hnc_ipc` 装进模块 `bin/`

```sh
# 在 daemon/build.sh 的末尾追加:
cp tools/prebuilt/${ARCH}/hnc_ipc ../../bin/
echo "[build] Copied tools/hnc_ipc to bin/"
```

`bin/hnc_ipc` 是 `apply_device_rule.sh` 通知 scheduler 必需的 socket
client, 不能省。

---

## 2. Patch hotspotd.c

四处 patch, 都是追加, 不删任何现有代码。

### 2.1 Patch A: includes 末尾

在文件顶部找到现有的 include 块 (~第 56 行附近):

```c
#include "hnc_helpers.h"
#include "hostname_cache.h"
#include "oui_override.h"
#include "mdns_worker.h"
```

**追加** 两行:

```c
#include "platform.h"        /* v5.0: SoC/ROM/offload 探测 */
#include "scheduler.h"       /* v5.0: offload 调度核心 */
```

### 2.2 Patch B: main() 启动 scheduler

在 `main()` 里找到这段 (~第 1547 行):

```c
    int worker_rc = hnc_mdns_worker_start();
    if (worker_rc != 0) {
        hlog("WARN: mdns worker start failed (rc=%d), re-resolve will fall back to mac",
             worker_rc);
    } else {
        hlog("mdns worker: started (queue size %d)", HNC_MDNS_QUEUE_SIZE);
    }
```

**之后追加**:

```c
    /* v5.0: 启动 offload scheduler (探测平台 + 选 adapter + 启 worker)
     *
     * 失败不致命: 内部会自动回落 null adapter, scheduler 仍可用,
     * 只是 disable_upstream / restore_upstream 变成 NOOP。
     * 这样 hotspotd 主路径 (设备扫描 / netlink / unix socket)
     * 完全不受 BPF 异常影响。 */
    int sched_rc = hnc_scheduler_init();
    if (sched_rc != 0) {
        hlog("WARN: scheduler init failed (rc=%d), offload control disabled",
             sched_rc);
    } else {
        hnc_offload_summary_t summ;
        hnc_scheduler_get_summary(&summ);
        hlog("scheduler: started (adapter=%s gran=%d upstream=%s/%d)",
             summ.adapter_name, summ.adapter_gran,
             summ.primary_upstream_ifname, summ.primary_upstream_ifindex);
    }
```

### 2.3 Patch C: control 命令派发加 OFFLOAD_*

找到 `handle_client(int cfd)` 函数里的命令派发块 (~第 992 行起):

```c
    if (strcmp(req, "GET_DEVICES") == 0) {
        ...
    } else if (strcmp(req, "REFRESH") == 0) {
        ...
    } else if (strcmp(req, "STATUS") == 0) {
        ...
    } else if (strcmp(req, "QUIT") == 0) {
        ...
    } else {
        send(cfd, "ERR:unknown command\n", 20, 0);
    }
```

**在 `else if (strcmp(req, "QUIT") == 0)` 之前**插入下面这段 (整段 ~50 行):

```c
    } else if (strncmp(req, "OFFLOAD_NOTIFY_LIMIT ", 21) == 0) {
        /* OFFLOAD_NOTIFY_LIMIT <mac> <0|1>
         * apply_device_rule.sh 在 tc 规则添加/删除后调 */
        char mac[32] = {0};
        int  flag    = -1;
        if (sscanf(req + 21, "%31s %d", mac, &flag) == 2 &&
            (flag == 0 || flag == 1)) {
            hnc_scheduler_notify_device_limit_changed(mac, flag);
            send(cfd, "OK\n", 3, 0);
        } else {
            send(cfd, "ERR:bad args (expect MAC 0|1)\n", 30, 0);
        }
    } else if (strcmp(req, "OFFLOAD_REFRESH") == 0) {
        hnc_scheduler_request_refresh();
        send(cfd, "OK:queued\n", 10, 0);
    } else if (strcmp(req, "OFFLOAD_STATUS") == 0) {
        hnc_offload_summary_t summ;
        hnc_scheduler_get_summary(&summ);
        char json[2048];
        int n = hnc_scheduler_summary_to_json(&summ, json, sizeof(json));
        if (n > 0) {
            send(cfd, json, (size_t)n, 0);
            send(cfd, "\n", 1, 0);
        } else {
            send(cfd, "ERR:summary serialize\n", 22, 0);
        }
    } else if (strcmp(req, "OFFLOAD_DISABLE_GLOBAL") == 0) {
        offload_err_t e = hnc_scheduler_force_disable_global();
        char resp[64];
        snprintf(resp, sizeof(resp), "%s:%s\n",
                 e == OFFLOAD_OK ? "OK" : "ERR",
                 offload_err_str(e));
        send(cfd, resp, strlen(resp), 0);
    } else if (strcmp(req, "OFFLOAD_RESTORE_GLOBAL") == 0) {
        offload_err_t e = hnc_scheduler_force_restore_global();
        char resp[64];
        snprintf(resp, sizeof(resp), "%s:%s\n",
                 e == OFFLOAD_OK ? "OK" : "ERR",
                 offload_err_str(e));
        send(cfd, resp, strlen(resp), 0);
```

### 2.4 Patch D: cleanup 加 scheduler_shutdown

找到 cleanup 段 (~第 1741 行):

```c
    /* v3.8.4: 停止异步 mDNS worker
     * 幂等,即使 worker 没启动也安全。... */
    hnc_mdns_worker_stop();
```

**之后追加** (在 `if (g_nl_fd >= 0) close(g_nl_fd);` 之前):

```c
    /* v5.0: 停 scheduler (停 offload worker + adapter shutdown)
     * 幂等, 必须在关 socket 之前, 让 adapter 干净关 BPF map fd */
    hnc_scheduler_shutdown();
```

---

## 3. Patch apply_device_rule.sh

加一个 helper 函数, 在两处调它。

### 3.1 加 helper (在文件顶部 `IPT=...TC=...JSON_SET=...` 那段后):

```sh
# v5.0: scheduler notify helper
# tc 规则发生变化后调, 让 scheduler 决定是否触发 BPF disable_upstream
HNC_IPC="$HNC_DIR/bin/hnc_ipc"
notify_offload() {
    local mac="$1"
    local flag="$2"   # 1=limited / 0=cleared
    [ -x "$HNC_IPC" ] || return 0   # 二进制不在 (老版本) → silently skip
    "$HNC_IPC" OFFLOAD_NOTIFY_LIMIT "$mac" "$flag" >> "$LOG" 2>&1 || \
        log "notify_offload mac=$mac flag=$flag failed (non-fatal)"
}
```

### 3.2 limit 分支: tc set_limit 成功后通知

找到 (~第 200 行):

```sh
        # 2. tc set_limit
        sh "$TC" set_limit "$IFACE" "$MID" "$DN_MBPS" "$UP_MBPS" "$IP" >> "$LOG" 2>&1 \
            || emit_err "tc set_limit failed"
        # 3. 写 rules.json (mark_id 已经在 gate_lock 内写过了, 这里只写其他字段)
```

**在 "3. 写 rules.json" 这行之前**插入:

```sh
        # v5.0: tc 规则就位, 通知 scheduler 决定是否触发 BPF offload disable
        notify_offload "$MAC" 1
```

### 3.3 clear 分支: tc remove 后通知

找到 (~第 225 行):

```sh
        # 1. tc remove (即使 iface/IP 缺也尝试,失败不报错 — ...)
        if [ -n "$IFACE" ] && [ "$IFACE" != "wlan0" ]; then
            sh "$TC" remove "$IFACE" "$MID" >> "$LOG" 2>&1 || log "tc remove warn (mid=$MID may not be applied)"
        fi
        # 2. iptables unmark
```

**在 "2. iptables unmark" 这行之前**插入:

```sh
        # v5.0: tc 规则已清, 通知 scheduler 可能恢复 offload
        notify_offload "$MAC" 0
```

注意: bl_add / bl_del (黑名单) 路径 **不** 调 notify_offload。
黑名单走 iptables DROP, 不影响 BPF offload 逻辑。
v5.x 如果要做"黑名单设备也强制走 slow path"再加。

---

## 4. 真机验证流程 (RMX5010)

### 4.1 平台探测

```sh
# 在 Termux 编完模块, 装上, 不必启动 hotspotd
adb shell su -c "/data/local/hnc/bin/platform_probe --pretty 2>/dev/null || \
                  /data/local/hnc/daemon/hotspotd/tools/prebuilt/arm64/platform_probe --pretty"
```

期望关键字段:

```
SoC.vendor            : qcom
SoC.model             : sun (或 SD8 Elite codename)
ROM.id                : coloros
Android.api           : 36
Kernel.parsed         : 6.6.102
Offload:
  bpf_tethering       : yes
  bpf_syscall_ok      : yes
Adapter selection: bpf (type=qcom_bpf gran=per_upstream)
```

任一不符: 把完整 JSON (`platform_probe` 不带 `--pretty`) 发给我看,
99% 是探测启发式漏了某个 ROM/SoC 标记。

### 4.2 启动 hotspotd 看 scheduler 日志

```sh
adb shell su -c "tail -F /data/local/hnc/logs/hotspotd.log" &
adb shell su -c "/system/bin/sh /data/local/hnc/service.sh"
# 期望 hotspotd.log 出现:
#   [hotspotd] scheduler: started (adapter=bpf gran=2 upstream=rmnet_data2/20)
#   [sched]   worker started (refresh interval 60s)
```

`upstream` 字段不是 `rmnet_data2` 也没关系, 重要的是 ifindex > 0。

### 4.3 模拟限速触发

```sh
# 任选一个连在热点上的设备 mac, 走正常 WebUI 加 5/2 Mbps 限速
# 或直接命令行:
adb shell su -c "/data/local/hnc/bin/apply_device_rule.sh limit aa:bb:cc:dd:ee:ff 5 2"

# 看 hotspotd.log 应该出现:
#   [sched] disable_upstream(ifindex=20 ifname=rmnet_data2): OK
#   [bpf] disable_upstream OK

# 验证 limit_map 真的写入 0:
adb shell su -c "cat /sys/fs/bpf/tethering/map_offload_tether_limit_map"
# 期望输出含: 20: 0
```

### 4.4 解除限速

```sh
adb shell su -c "/data/local/hnc/bin/apply_device_rule.sh clear aa:bb:cc:dd:ee:ff"

# 看 hotspotd.log:
#   [sched] restore_upstream(ifindex=20): OK

adb shell su -c "cat /sys/fs/bpf/tethering/map_offload_tether_limit_map"
# 期望: 20: 18446744073709551615
```

### 4.5 多设备共存

加两个设备的限速, 然后只解除一个 → `limit_map[20]` 应保持 0
(集合还有 1 个设备), 解除最后一个才恢复 U64_MAX。

```sh
adb shell su -c "/data/local/hnc/bin/hnc_ipc OFFLOAD_STATUS | python -m json.tool"
# 看 limited_device_count 数字
```

### 4.6 重启幂等

```sh
adb shell su -c "kill -TERM \$(cat /data/local/hnc/run/hotspotd.pid)"
sleep 2
adb shell su -c "/system/bin/sh /data/local/hnc/service.sh"
```

**已知行为 (alpha.1 限制)**: hotspotd 重启后 scheduler 内部
`limited_macs` 集合是空的, 但 BPF `limit_map` 里之前写过的 0 还在
(framework 不主动回写)。这意味着重启后 offload 仍然 disable, 但
scheduler 以为没限速设备。下次有任何设备的 limit 规则发生变化时
(包括 watchdog restore_rules 触发的), 会重新对齐。

**v5.0 alpha.2 计划**: scheduler 启动时遍历 `rules.json` 的
`devices.*.limit_enabled=true`, 自动重建集合。

### 4.7 极端: 强制 offload 关掉

不依赖 scheduler 状态, 直接驱动 adapter:

```sh
adb shell su -c "/data/local/hnc/bin/hnc_ipc OFFLOAD_DISABLE_GLOBAL"
adb shell su -c "/data/local/hnc/bin/hnc_ipc OFFLOAD_RESTORE_GLOBAL"
```

或者绕过 hotspotd 直接用 offload_ctl (调试场景):

```sh
adb shell su -c "/data/local/hnc/daemon/hotspotd/tools/prebuilt/arm64/offload_ctl status"
adb shell su -c "/data/local/hnc/daemon/hotspotd/tools/prebuilt/arm64/offload_ctl disable_upstream rmnet_data2"
```

---

## 5. 回滚

### 5.1 软回滚 (保留代码, 关 offload 路径)

最快: 在 `hnc_scheduler_init()` 之前加一行环境变量检查, 让 daemon
启动时跳过 scheduler。或更简单, 把 hotspotd 启动参数加 `-l /dev/null`
之后, 手动 `kill scheduler_thread` 不可行 (代码内嵌)。

正规: 还原 hotspotd.c 的 4 处 patch + apply_device_rule.sh 的 patch,
重编译。

### 5.2 硬回滚 (退回 v4.1)

```sh
# 装 v4.1.0-rc3.1.34 zip 直接覆盖
adb shell su -c "ksud module install /sdcard/HNC-v4_1_0-rc3_1_34-arm64.zip"
adb reboot
```

scheduler 状态全在内存, 重启即清。BPF `limit_map` 的写入会被
framework 在下次 stats sync 时重置为 U64_MAX (实测 5-30s 内)。

如果担心残留, 手动:

```sh
adb shell su -c "for k in 20 21 22; do
    printf '\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff' > /tmp/v
    # 或者直接重启 tethering 服务
done
adb shell su -c "stop tethering; start tethering"  # 或重开热点
```

---

## 6. 已知 alpha.1 限制 / TODO

| # | 限制 | v5.0 计划 |
|---|---|---|
| 1 | 重启后 scheduler 集合丢失 | alpha.2 启动时从 rules.json 重建 |
| 2 | 黑名单设备不触发 offload disable | beta 评估是否需要 |
| 3 | per-device 粒度未实现 | alpha.3 (路线 C: conntrack 监听) |
| 4 | 只支持 IPv4 默认路由探测 | beta 接 RTM_NEWROUTE 监听 |
| 5 | MTK PPE / 三星 NSS adapter 占位 | v5.1 / v5.2 |
| 6 | WebUI 无 /api/offload 集成 | alpha.2 (Go httpd patch) |
| 7 | check_offload.sh 仍走 sysfs 而非 daemon | alpha.2 切到 hnc_ipc |
| 8 | platform_probe 探测不到 APEX 版本 | beta 用 pm 命令补 |

---

## 7. 提交建议

每一组 patch 单独 commit, 便于问题定位时 git bisect:

```
v5.0-alpha.1 commit 1: add offload abstraction layer (adapter.h + null + bpf)
v5.0-alpha.1 commit 2: add platform probe + tools
v5.0-alpha.1 commit 3: add scheduler + worker thread
v5.0-alpha.1 commit 4: integrate scheduler into hotspotd (4 patches)
v5.0-alpha.1 commit 5: integrate notify_offload into apply_device_rule.sh
v5.0-alpha.1 commit 6: add hnc_ipc client + ship in bin/
v5.0-alpha.1 commit 7: bump module.prop + CHANGELOG
```

`module.prop` 建议:

```
version=v5.0.0-alpha.1
versionCode=50001
description=...热点带宽/延迟/黑白名单管理 · v5.0 引入 BPF offload 抽象层
```

---

## 8. 报问题给我时带的最小信息

```sh
adb shell su -c "/data/local/hnc/bin/platform_probe"   > platform.json
adb shell su -c "/data/local/hnc/bin/hnc_ipc OFFLOAD_STATUS"  > offload.json
adb shell su -c "tail -n 200 /data/local/hnc/logs/hotspotd.log" > hotspotd.log
adb shell su -c "cat /sys/fs/bpf/tethering/map_offload_tether_limit_map" > limit_map.txt
```

四个文件就足够定位 90% 的 alpha.1 问题。
