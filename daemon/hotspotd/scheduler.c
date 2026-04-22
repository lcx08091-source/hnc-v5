/* scheduler.c — HNC v5.0 offload 调度核心实现
 *
 * 设计要点见 scheduler.h
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "scheduler.h"
#include "platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <ctype.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>

#include <net/if.h>
#include <sys/socket.h>

/* ══════════════════════════════════════════════════════════
 * 内部状态
 * ══════════════════════════════════════════════════════════ */

static struct {
    int               initialized;

    /* 选中的 adapter (init 时固定, shutdown 前不变) */
    offload_adapter_t *adapter;

    /* 主调度状态 lock */
    pthread_mutex_t   lock;

    /* 受限设备 mac 集合 (小写存储, 简单线性数组)
     *   "aa:bb:cc:dd:ee:ff\0" = 18 bytes per slot
     *   256 slot * 18 = 4.5 KB, cache 友好
     *   线性 find/insert/remove O(N), 256 大小下 < 1µs
     */
    char              limited_macs[HNC_SCHED_MAX_LIMITED_DEVICES][18];
    int               limited_count;

    /* 当前主上游 (默认路由的 oif)
     * v5.0 alpha.1: 启动时探测 + 在每次 0→>0 转换时重探一次
     * v5.0 beta:    upstream.c 模块替换 (RTM_NEWROUTE 监听)
     */
    int               primary_upstream_ifindex;
    char              primary_upstream_ifname[HNC_SCHED_IFNAME_LEN];

    /* worker 线程 */
    pthread_t         worker_tid;
    int               worker_started;
    int               worker_should_stop;
    int               worker_refresh_requested;
    int64_t           worker_last_refresh_ts;
    /* refresh 完成计数 (单调递增, 测试与前端可用于"refresh 是否真的发生"
     * 的判断, 不依赖 wall clock 秒精度) */
    int64_t           worker_refresh_count;

    pthread_mutex_t   worker_lock;
    pthread_cond_t    worker_cond;
} sched = {
    .initialized              = 0,
    .adapter                  = NULL,
    .limited_count            = 0,
    .primary_upstream_ifindex = 0,
    .primary_upstream_ifname  = {0},
    .worker_started           = 0,
    .worker_should_stop       = 0,
    .worker_refresh_requested = 0,
    .worker_last_refresh_ts   = 0,
    .worker_refresh_count     = 0,
};

/* ══════════════════════════════════════════════════════════
 * 内部小工具: mac 规范化 + 集合操作
 * ══════════════════════════════════════════════════════════ */

/* 规范化 mac: 小写, 严格 17 字符 "aa:bb:cc:dd:ee:ff"
 * 输入非法 (长度不对, 含非 hex/colon) → 返 -1
 * 输出始终 NUL-terminated
 */
static int normalize_mac(const char *in, char *out)
{
    if (in == NULL) return -1;
    for (int i = 0; i < 17; i++) {
        char c = in[i];
        if (c == '\0') return -1;
        if (i % 3 == 2) {
            if (c != ':') return -1;
            out[i] = ':';
        } else {
            if (!isxdigit((unsigned char)c)) return -1;
            out[i] = (char)tolower((unsigned char)c);
        }
    }
    out[17] = '\0';
    if (in[17] != '\0' && in[17] != '\n' && in[17] != ' ') return -1;
    return 0;
}

/* 在 limited_macs 中找 mac 的索引, 找不到返 -1
 * 调用方需持 sched.lock
 */
static int limited_set_find(const char *mac)
{
    for (int i = 0; i < sched.limited_count; i++)
        if (strcmp(sched.limited_macs[i], mac) == 0) return i;
    return -1;
}

/* 添加, 已存在/集合满 → 返 -1; 成功返 新索引
 * 调用方需持 sched.lock
 */
static int limited_set_add(const char *mac)
{
    if (limited_set_find(mac) >= 0) return -1;
    if (sched.limited_count >= HNC_SCHED_MAX_LIMITED_DEVICES) {
        fprintf(stderr, "[sched] limited set full (max %d), drop %s\n",
                HNC_SCHED_MAX_LIMITED_DEVICES, mac);
        return -1;
    }
    int idx = sched.limited_count++;
    snprintf(sched.limited_macs[idx], sizeof(sched.limited_macs[idx]), "%s", mac);
    return idx;
}

/* 移除, 不存在 → 返 -1; 成功返 0
 * 调用方需持 sched.lock
 */
static int limited_set_remove(const char *mac)
{
    int idx = limited_set_find(mac);
    if (idx < 0) return -1;
    /* 末尾元素填洞 */
    int last = --sched.limited_count;
    if (idx != last)
        memcpy(sched.limited_macs[idx], sched.limited_macs[last],
               sizeof(sched.limited_macs[idx]));
    sched.limited_macs[last][0] = '\0';
    return 0;
}

/* ══════════════════════════════════════════════════════════
 * 上游探测
 *
 * 读 /proc/net/route 找 default route (Destination=00000000) 的 Iface
 *
 * 格式 (字段 tab 分隔):
 *   Iface  Destination  Gateway  Flags  RefCnt  Use  Metric  Mask  ...
 *   rmnet_data2  00000000  XXXXXXXX  0003  0  0  0  00000000 ...
 *
 * v5.0 alpha.1 限制:
 *   - 只看 IPv4 默认路由
 *   - 多上游(metric 不同的多条 default route)只取第一条
 *   - 不感知 tethering 内的 NAT 路径
 *   v5.0 beta 由 upstream.c 替换 (走 netlink RTM_NEWROUTE)
 * ══════════════════════════════════════════════════════════ */

/* 内部使用, 不加锁 (调用方负责)
 * 成功填 ifindex/ifname 返 0; 失败返 -1
 */
static int detect_primary_upstream(int *ifindex_out, char *ifname_out, size_t ifname_size)
{
    FILE *f = fopen("/proc/net/route", "r");
    if (!f) return -1;

    char line[512];
    /* skip header */
    if (fgets(line, sizeof(line), f) == NULL) {
        fclose(f);
        return -1;
    }

    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        /* Linux 网卡名最长 15 字符 (IFNAMSIZ-1), 用 IFNAMSIZ buffer */
        char iface[IFNAMSIZ];
        char dest[16];
        unsigned int flags;
        /* sscanf: Iface Destination Gateway Flags ... */
        if (sscanf(line, "%15s %15s %*s %x", iface, dest, &flags) != 3)
            continue;
        if (strcmp(dest, "00000000") != 0) continue;
        /* 默认路由必须 UP (RTF_UP=0x1) */
        if (!(flags & 0x1)) continue;

        unsigned int idx = if_nametoindex(iface);
        if (idx == 0) continue;

        *ifindex_out = (int)idx;
        /* iface 已限制 15 字符, 写入 ifname_size>=16 的 buf 不会截断 */
        snprintf(ifname_out, ifname_size, "%s", iface);
        found = 1;
        break;
    }
    fclose(f);
    return found ? 0 : -1;
}

/* 公开 wrap, 加锁 + 缓存
 * 仅在内部触发: init / 0→>0 转换时
 */
static void refresh_primary_upstream_locked(void)
{
    int idx = 0;
    char name[HNC_SCHED_IFNAME_LEN] = {0};
    if (detect_primary_upstream(&idx, name, sizeof(name)) == 0) {
        if (idx != sched.primary_upstream_ifindex ||
            strcmp(name, sched.primary_upstream_ifname) != 0) {
            fprintf(stderr, "[sched] primary upstream: %s (ifindex=%d)\n", name, idx);
        }
        sched.primary_upstream_ifindex = idx;
        snprintf(sched.primary_upstream_ifname,
                 sizeof(sched.primary_upstream_ifname), "%s", name);
    } else {
        fprintf(stderr, "[sched] primary upstream not found (no default route)\n");
        sched.primary_upstream_ifindex = 0;
        sched.primary_upstream_ifname[0] = '\0';
    }
}

/* ══════════════════════════════════════════════════════════
 * Adapter 触发 helper
 *
 * 根据 adapter granularity 选合适操作:
 *   PER_UPSTREAM → disable_upstream(primary_upstream)
 *   GLOBAL       → disable_global
 *   NONE         → no-op
 *
 * 调用方需持 sched.lock (读 primary_upstream)
 * adapter 调用本身不需 lock (adapter 内部自管)
 * ══════════════════════════════════════════════════════════ */

static void trigger_adapter_disable_locked(void)
{
    if (sched.adapter == NULL) return;
    offload_adapter_t *a = sched.adapter;

    switch (a->granularity) {
    case OFFLOAD_GRAN_PER_UPSTREAM: {
        if (sched.primary_upstream_ifindex <= 0) {
            fprintf(stderr, "[sched] no primary upstream, can't disable_upstream\n");
            return;
        }
        if (a->disable_upstream == NULL) {
            fprintf(stderr, "[sched] adapter %s missing disable_upstream\n", a->name);
            return;
        }
        offload_err_t e = a->disable_upstream(sched.primary_upstream_ifindex);
        fprintf(stderr, "[sched] disable_upstream(ifindex=%d ifname=%s): %s\n",
                sched.primary_upstream_ifindex,
                sched.primary_upstream_ifname,
                offload_err_str(e));
        break;
    }
    case OFFLOAD_GRAN_GLOBAL: {
        if (a->disable_global == NULL) return;
        offload_err_t e = a->disable_global();
        fprintf(stderr, "[sched] disable_global: %s\n", offload_err_str(e));
        break;
    }
    case OFFLOAD_GRAN_NONE:
    case OFFLOAD_GRAN_PER_DEVICE:    /* alpha.1 不实现 per-device 路径 */
    default:
        break;
    }
}

static void trigger_adapter_restore_locked(void)
{
    if (sched.adapter == NULL) return;
    offload_adapter_t *a = sched.adapter;

    switch (a->granularity) {
    case OFFLOAD_GRAN_PER_UPSTREAM: {
        if (sched.primary_upstream_ifindex <= 0) return;
        if (a->restore_upstream == NULL) return;
        offload_err_t e = a->restore_upstream(sched.primary_upstream_ifindex);
        fprintf(stderr, "[sched] restore_upstream(ifindex=%d): %s\n",
                sched.primary_upstream_ifindex, offload_err_str(e));
        break;
    }
    case OFFLOAD_GRAN_GLOBAL: {
        if (a->restore_global == NULL) return;
        offload_err_t e = a->restore_global();
        fprintf(stderr, "[sched] restore_global: %s\n", offload_err_str(e));
        break;
    }
    case OFFLOAD_GRAN_NONE:
    case OFFLOAD_GRAN_PER_DEVICE:
    default:
        break;
    }
}

/* ══════════════════════════════════════════════════════════
 * Worker 线程
 *
 * 等待 worker_cond, 任一条件唤醒:
 *   1) worker_should_stop=1 → 退出
 *   2) worker_refresh_requested=1 → 立即跑 refresh_active
 *   3) timedwait 60s 超时 → 周期 refresh
 *
 * refresh_active 阻塞 5s (sleep), 期间 worker_lock 释放,
 * 主线程仍可 request_refresh / shutdown (会在下次循环检测到)
 * ══════════════════════════════════════════════════════════ */

static void *worker_main(void *arg)
{
    (void)arg;
    fprintf(stderr, "[sched] worker started (refresh interval %ds)\n",
            HNC_SCHED_REFRESH_INTERVAL_SEC);

    while (1) {
        pthread_mutex_lock(&sched.worker_lock);

        /* timed wait until: should_stop / refresh_requested / 60s timeout */
        if (!sched.worker_should_stop && !sched.worker_refresh_requested) {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            ts.tv_sec += HNC_SCHED_REFRESH_INTERVAL_SEC;
            pthread_cond_timedwait(&sched.worker_cond, &sched.worker_lock, &ts);
        }

        if (sched.worker_should_stop) {
            pthread_mutex_unlock(&sched.worker_lock);
            break;
        }
        sched.worker_refresh_requested = 0;
        pthread_mutex_unlock(&sched.worker_lock);

        /* 跑 refresh (可能 sleep 5s) */
        if (sched.adapter && sched.adapter->refresh_active) {
            offload_err_t e = sched.adapter->refresh_active();
            if (e != OFFLOAD_OK) {
                fprintf(stderr, "[sched] refresh_active: %s\n", offload_err_str(e));
            }
        }
        sched.worker_last_refresh_ts = (int64_t)time(NULL);
        sched.worker_refresh_count++;
    }

    fprintf(stderr, "[sched] worker stopped\n");
    return NULL;
}

/* ══════════════════════════════════════════════════════════
 * 初始化 / 关闭
 * ══════════════════════════════════════════════════════════ */

int hnc_scheduler_init(void)
{
    if (sched.initialized) return 0;

    /* 探测平台 */
    platform_probe();

    /* 选 adapter */
    sched.adapter = offload_select_adapter();
    if (sched.adapter == NULL) {
        fprintf(stderr, "[sched] FATAL: no adapter selected (not even null!)\n");
        return -1;
    }

    /* init adapter, 失败回落 null */
    offload_err_t e = sched.adapter->init();
    if (e != OFFLOAD_OK) {
        fprintf(stderr, "[sched] adapter %s init failed: %s, falling back to null\n",
                sched.adapter->name, offload_err_str(e));
        /* 找 null adapter */
        extern offload_adapter_t adapter_null;
        sched.adapter = &adapter_null;
        offload_set_active_adapter(sched.adapter);
        sched.adapter->init();   /* null 永远成功 */
    } else {
        /* schema self-check */
        if (sched.adapter->self_check) {
            offload_err_t sc = sched.adapter->self_check();
            if (sc != OFFLOAD_OK) {
                fprintf(stderr, "[sched] adapter %s self_check FAIL: %s, falling back\n",
                        sched.adapter->name, offload_err_str(sc));
                sched.adapter->shutdown();
                extern offload_adapter_t adapter_null;
                sched.adapter = &adapter_null;
                offload_set_active_adapter(sched.adapter);
                sched.adapter->init();
            }
        }
    }

    /* 初始化 lock */
    pthread_mutex_init(&sched.lock, NULL);
    pthread_mutex_init(&sched.worker_lock, NULL);
    pthread_cond_init(&sched.worker_cond, NULL);

    /* 初次探测上游 */
    pthread_mutex_lock(&sched.lock);
    refresh_primary_upstream_locked();
    pthread_mutex_unlock(&sched.lock);

    /* 启动 worker 线程 */
    sched.worker_should_stop = 0;
    sched.worker_refresh_requested = 0;
    int rc = pthread_create(&sched.worker_tid, NULL, worker_main, NULL);
    if (rc != 0) {
        fprintf(stderr, "[sched] pthread_create worker failed: %d\n", rc);
        sched.adapter->shutdown();
        return -1;
    }
    sched.worker_started = 1;

    sched.initialized = 1;
    fprintf(stderr, "[sched] init OK (adapter=%s gran=%s upstream=%s/%d)\n",
            sched.adapter->name,
            offload_gran_str(sched.adapter->granularity),
            sched.primary_upstream_ifname,
            sched.primary_upstream_ifindex);
    return 0;
}

void hnc_scheduler_shutdown(void)
{
    if (!sched.initialized) return;

    /* 停 worker */
    if (sched.worker_started) {
        pthread_mutex_lock(&sched.worker_lock);
        sched.worker_should_stop = 1;
        pthread_cond_signal(&sched.worker_cond);
        pthread_mutex_unlock(&sched.worker_lock);
        pthread_join(sched.worker_tid, NULL);
        sched.worker_started = 0;
    }

    /* shutdown adapter */
    if (sched.adapter && sched.adapter->shutdown) {
        sched.adapter->shutdown();
    }

    pthread_mutex_destroy(&sched.lock);
    pthread_mutex_destroy(&sched.worker_lock);
    pthread_cond_destroy(&sched.worker_cond);

    sched.initialized = 0;
    fprintf(stderr, "[sched] shutdown done\n");
}

/* ══════════════════════════════════════════════════════════
 * Notify
 * ══════════════════════════════════════════════════════════ */

void hnc_scheduler_notify_device_limit_changed(const char *mac, int is_limited)
{
    if (!sched.initialized) return;

    char norm[18];
    if (normalize_mac(mac, norm) != 0) {
        fprintf(stderr, "[sched] notify: invalid mac '%s'\n", mac ? mac : "(null)");
        return;
    }

    int old_count, new_count;
    int triggered_disable = 0, triggered_restore = 0;

    pthread_mutex_lock(&sched.lock);
    old_count = sched.limited_count;

    if (is_limited) {
        limited_set_add(norm);    /* 已存在则 noop */
    } else {
        limited_set_remove(norm); /* 不存在则 noop */
    }
    new_count = sched.limited_count;

    /* 状态机: 0 → >0 / >0 → 0 */
    if (old_count == 0 && new_count > 0) {
        /* 重新探测上游 (上次可能是冷启时, 上游可能已切换) */
        refresh_primary_upstream_locked();
        triggered_disable = 1;
    } else if (old_count > 0 && new_count == 0) {
        triggered_restore = 1;
    }

    /* 注: trigger_* 内部不再读 limited_count, 只读 primary_upstream
     * 与 adapter 状态。adapter 操作本身已是线程安全 (file-static lock free)
     * 所以可以在持 sched.lock 时调 (调用 < 1ms 不会成为瓶颈) */
    if (triggered_disable)  trigger_adapter_disable_locked();
    if (triggered_restore)  trigger_adapter_restore_locked();

    pthread_mutex_unlock(&sched.lock);

    if (triggered_disable || triggered_restore) {
        /* 状态变化后请求 worker 立即 refresh, 让 active 状态尽快反映 */
        hnc_scheduler_request_refresh();
    }
}

void hnc_scheduler_request_refresh(void)
{
    if (!sched.initialized || !sched.worker_started) return;
    pthread_mutex_lock(&sched.worker_lock);
    sched.worker_refresh_requested = 1;
    pthread_cond_signal(&sched.worker_cond);
    pthread_mutex_unlock(&sched.worker_lock);
}

/* ══════════════════════════════════════════════════════════
 * 强制操作 (control 命令直接驱动)
 * ══════════════════════════════════════════════════════════ */

offload_err_t hnc_scheduler_force_disable_global(void)
{
    if (!sched.initialized || sched.adapter == NULL) return OFFLOAD_EINTERNAL;
    if (sched.adapter->disable_global == NULL)       return OFFLOAD_ENOTSUP;
    return sched.adapter->disable_global();
}

offload_err_t hnc_scheduler_force_restore_global(void)
{
    if (!sched.initialized || sched.adapter == NULL) return OFFLOAD_EINTERNAL;
    if (sched.adapter->restore_global == NULL)       return OFFLOAD_ENOTSUP;

    pthread_mutex_lock(&sched.lock);
    sched.limited_count = 0;     /* 强制 restore 隐含清空集合 */
    pthread_mutex_unlock(&sched.lock);

    return sched.adapter->restore_global();
}

/* ══════════════════════════════════════════════════════════
 * 查询
 * ══════════════════════════════════════════════════════════ */

void hnc_scheduler_get_summary(hnc_offload_summary_t *out)
{
    if (out == NULL) return;
    memset(out, 0, sizeof(*out));

    if (!sched.initialized || sched.adapter == NULL) {
        snprintf(out->adapter_name, sizeof(out->adapter_name), "uninitialized");
        return;
    }

    /* Adapter 元 + 状态 (lock-free) */
    snprintf(out->adapter_name, sizeof(out->adapter_name),
             "%s", sched.adapter->name);
    out->adapter_type = (int)sched.adapter->type;
    out->adapter_gran = (int)sched.adapter->granularity;

    offload_status_t st;
    memset(&st, 0, sizeof(st));
    if (sched.adapter->status) sched.adapter->status(&st);

    out->active                  = st.active;
    out->last_refresh_ts         = st.last_refresh_ts;
    out->last_delta_bytes        = st.last_delta_bytes;
    out->globally_disabled       = st.globally_disabled;
    out->disabled_upstream_count = st.disabled_upstream_count;
    int n = st.disabled_upstream_count;
    int cap = (int)(sizeof(out->disabled_upstream_ifindex) /
                    sizeof(out->disabled_upstream_ifindex[0]));
    if (n > cap) n = cap;
    for (int i = 0; i < n; i++)
        out->disabled_upstream_ifindex[i] = st.disabled_upstream_ifindex[i];

    /* Scheduler 内部 (加锁) */
    pthread_mutex_lock(&sched.lock);
    out->limited_device_count    = sched.limited_count;
    out->primary_upstream_ifindex = sched.primary_upstream_ifindex;
    snprintf(out->primary_upstream_ifname,
             sizeof(out->primary_upstream_ifname),
             "%s", sched.primary_upstream_ifname);
    pthread_mutex_unlock(&sched.lock);

    out->worker_running          = sched.worker_started;
    out->worker_last_refresh_ts  = sched.worker_last_refresh_ts;
    out->worker_refresh_count    = sched.worker_refresh_count;
}

int hnc_scheduler_summary_to_json(const hnc_offload_summary_t *s,
                                   char *buf, size_t buf_size)
{
    if (s == NULL || buf == NULL || buf_size == 0) return -1;

    /* disabled_upstream_ifindex JSON 数组 */
    char dis_arr[128] = "[]";
    if (s->disabled_upstream_count > 0) {
        char *p = dis_arr;
        char *end = dis_arr + sizeof(dis_arr);
        int written = snprintf(p, (size_t)(end - p), "[");
        if (written < 0 || written >= (end - p)) goto trunc;
        p += written;
        for (int i = 0; i < s->disabled_upstream_count && p < end; i++) {
            written = snprintf(p, (size_t)(end - p), "%s%d",
                               i ? "," : "",
                               s->disabled_upstream_ifindex[i]);
            if (written < 0 || written >= (end - p)) goto trunc;
            p += written;
        }
        if (p < end) snprintf(p, (size_t)(end - p), "]");
    }
    goto ok;
trunc:
    snprintf(dis_arr, sizeof(dis_arr), "[]");
ok:
    /* clang 默认 -std=c11 下 "label followed by declaration" 是 C23 扩展,
     * 加一个空语句让标签后跟语句而非声明 */
    (void)0;

    int n = snprintf(buf, buf_size,
        "{"
        "\"adapter\":{\"name\":\"%s\",\"type\":%d,\"granularity\":%d},"
        "\"active\":%s,"
        "\"last_refresh_ts\":%lld,"
        "\"last_delta_bytes\":%llu,"
        "\"globally_disabled\":%s,"
        "\"disabled_upstream_count\":%d,"
        "\"disabled_upstream_ifindex\":%s,"
        "\"limited_device_count\":%d,"
        "\"primary_upstream_ifindex\":%d,"
        "\"primary_upstream_ifname\":\"%s\","
        "\"worker_running\":%s,"
        "\"worker_last_refresh_ts\":%lld,"
        "\"worker_refresh_count\":%lld"
        "}",
        s->adapter_name,
        s->adapter_type,
        s->adapter_gran,
        s->active ? "true" : "false",
        (long long)s->last_refresh_ts,
        (unsigned long long)s->last_delta_bytes,
        s->globally_disabled ? "true" : "false",
        s->disabled_upstream_count,
        dis_arr,
        s->limited_device_count,
        s->primary_upstream_ifindex,
        s->primary_upstream_ifname,
        s->worker_running ? "true" : "false",
        (long long)s->worker_last_refresh_ts,
        (long long)s->worker_refresh_count
    );

    if (n < 0 || (size_t)n >= buf_size) return -1;
    return n;
}
