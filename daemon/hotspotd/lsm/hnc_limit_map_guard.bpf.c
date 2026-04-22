// SPDX-License-Identifier: GPL-2.0
//
// hnc_limit_map_guard.bpf.c — HNC v5.0 BPF LSM 程序
//
// 拦截 system_server 对 tethering limit_map 的 BPF_MAP_UPDATE_ELEM,
// 当且仅当下列条件全部命中时返回 -EPERM:
//   - cmd == BPF_MAP_UPDATE_ELEM
//   - 目标 map id == ctrl.protected_map_id (userspace 注入)
//   - 目标 key (ifindex) == ctrl.protected_ifindex (userspace 注入)
//   - 写入 value == U64_MAX
//   - caller pid != ctrl.hotspotd_pid (白名单)
// 其他情况一律 return 0 (放行),零干扰。

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

#define EPERM 1
#define U64_MAX 0xFFFFFFFFFFFFFFFFULL
#define BPF_MAP_UPDATE_ELEM_CMD 2  // include/uapi/linux/bpf.h enum bpf_cmd

// ─── 控制 map (userspace 写,kernel 读) ────────────────────────────
struct hnc_lsm_ctrl {
    __u32 protected_map_id;
    __u32 protected_ifindex;
    __u32 hotspotd_pid;
    __u32 enabled;     // 1=拦截+记录, 0=只记录不拦截 (调试)
};

struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __type(key, __u32);
    __type(value, struct hnc_lsm_ctrl);
    __uint(max_entries, 1);
} hnc_ctrl_map SEC(".maps");

// ─── 事件 ringbuf ─────────────────────────────────────────────────
struct hnc_lsm_event {
    __u64 ts_ns;
    __u32 caller_pid;
    __u32 caller_uid;
    __u64 attempted_value;
    __u32 ifindex;
    __u32 verdict;     // 0=allow, 1=deny
    char  comm[16];
};

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 64 * 1024);
} hnc_lsm_events SEC(".maps");

// ─── 主 LSM hook ─────────────────────────────────────────────────
// security_bpf(int cmd, union bpf_attr *attr, unsigned int size)
// LSM ret 0 = allow, 负数 = deny

SEC("lsm/bpf")
int BPF_PROG(hnc_check_bpf,
             int cmd,
             union bpf_attr *attr,
             unsigned int size,
             int prev_ret)
{
    // LSM 链规则:之前的 LSM 已 deny → 必须保持 deny
    if (prev_ret != 0)
        return prev_ret;

    if (cmd != BPF_MAP_UPDATE_ELEM_CMD)
        return 0;

    __u32 ckey = 0;
    struct hnc_lsm_ctrl *ctrl = bpf_map_lookup_elem(&hnc_ctrl_map, &ckey);
    if (!ctrl)
        return 0;
    if (ctrl->protected_map_id == 0)  // 还没初始化
        return 0;

    // ─── 1. 反查 map_fd → bpf_map * → map id ───────────────
    __u32 map_fd = BPF_CORE_READ(attr, map_fd);

    struct task_struct *task = (struct task_struct *)bpf_get_current_task();
    struct files_struct *files = BPF_CORE_READ(task, files);
    if (!files) return 0;

    struct fdtable *fdt = BPF_CORE_READ(files, fdt);
    if (!fdt) return 0;

    __u32 max_fds = BPF_CORE_READ(fdt, max_fds);
    if (map_fd >= max_fds) return 0;
    // 位掩码强制证明边界 (向 verifier 证明 map_fd 不会越界)
    map_fd &= 0xFFFF;
    if (map_fd >= max_fds) return 0;

    struct file **fdarr = BPF_CORE_READ(fdt, fd);
    if (!fdarr) return 0;

    struct file *fp = NULL;
    bpf_probe_read_kernel(&fp, sizeof(fp), &fdarr[map_fd]);
    if (!fp) return 0;

    struct bpf_map *map = (struct bpf_map *)BPF_CORE_READ(fp, private_data);
    if (!map) return 0;

    __u32 mid = BPF_CORE_READ(map, id);
    if (mid != ctrl->protected_map_id)
        return 0;

    // ─── 2. 检查 key (ifindex) ──────────────────────────────
    __u64 key_uptr = BPF_CORE_READ(attr, key);
    __u32 ifindex = 0;
    bpf_probe_read_user(&ifindex, sizeof(ifindex), (void *)key_uptr);
    if (ifindex != ctrl->protected_ifindex)
        return 0;

    // ─── 3. 白名单 hotspotd ─────────────────────────────────
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 caller_tgid = pid_tgid >> 32;
    if (caller_tgid == ctrl->hotspotd_pid)
        return 0;   // 我们自己写,放行

    // ─── 4. 读 value, 只对 U64_MAX 拒绝 ──────────────────────
    __u64 val_uptr = BPF_CORE_READ(attr, value);
    __u64 val = 0;
    bpf_probe_read_user(&val, sizeof(val), (void *)val_uptr);

    // ─── 5. 记录事件 ────────────────────────────────────────
    __u32 verdict = (val == U64_MAX) ? 1 : 0;
    struct hnc_lsm_event *ev = bpf_ringbuf_reserve(
        &hnc_lsm_events, sizeof(*ev), 0);
    if (ev) {
        ev->ts_ns = bpf_ktime_get_ns();
        ev->caller_pid = caller_tgid;
        ev->caller_uid = bpf_get_current_uid_gid() & 0xFFFFFFFF;
        ev->attempted_value = val;
        ev->ifindex = ifindex;
        ev->verdict = verdict;
        bpf_get_current_comm(&ev->comm, sizeof(ev->comm));
        bpf_ringbuf_submit(ev, 0);
    }

    if (verdict && ctrl->enabled)
        return -EPERM;

    return 0;
}

char _license[] SEC("license") = "GPL";
