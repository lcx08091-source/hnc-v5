/* hnc_lsm_loader.c — HNC v5.0 BPF LSM Limit Map Guard 用户态加载器
 *
 * 不依赖 libbpf 运行时, 直接 sys_bpf 调用 (跟 adapter_bpf.c 一脉相承).
 *
 * 工作流程:
 *   1. 检测 BPF LSM 可用 (/sys/kernel/security/lsm 含 bpf)
 *   2. 拿目标 limit_map 的 map_id (BPF_OBJ_GET_INFO_BY_FD)
 *   3. 解析 .bpf.o ELF, 建立 ctrl_map / ringbuf_map
 *   4. fixup BPF 程序里的 map_fd (relocations)
 *   5. BPF_PROG_LOAD (kind=LSM, attach_type=LSM_MAC, attach_btf_id=security_bpf)
 *   6. populate ctrl_map 写入 (map_id, ifindex, hotspotd_pid, enabled)
 *   7. BPF_RAW_TRACEPOINT_OPEN attach LSM hook (得到 link fd)
 *   8. 启 pthread 消费 ringbuf 事件, 更新 status 计数
 *
 * 任何步骤失败 → state = FAILED, fail_reason 记录, 不抛错 (graceful degrade).
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "hnc_lsm_loader.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/epoll.h>
#include <sys/stat.h>
#include <linux/bpf.h>
#include <elf.h>

/* ══════════════════════════════════════════════════════════
 * sys_bpf wrapper (与 adapter_bpf.c 一致)
 * ══════════════════════════════════════════════════════════ */

#ifndef __NR_bpf
#  if defined(__aarch64__)
#    define __NR_bpf 280
#  elif defined(__arm__)
#    define __NR_bpf 386
#  elif defined(__x86_64__)
#    define __NR_bpf 321
#  elif defined(__i386__)
#    define __NR_bpf 357
#  else
#    error "unknown arch"
#  endif
#endif

static inline long sys_bpf(enum bpf_cmd cmd, union bpf_attr *attr, unsigned int size)
{
    return syscall(__NR_bpf, cmd, attr, size);
}

/* ══════════════════════════════════════════════════════════
 * 内部状态
 * ══════════════════════════════════════════════════════════ */

/* 控制 map value (跟 .bpf.c 里的 struct 严格对齐) */
struct hnc_lsm_ctrl_v {
    uint32_t protected_map_id;
    uint32_t protected_ifindex;
    uint32_t hotspotd_pid;
    uint32_t enabled;
};

/* ringbuf 事件 (跟 .bpf.c 里的 struct 严格对齐) */
struct hnc_lsm_event_v {
    uint64_t ts_ns;
    uint32_t caller_pid;
    uint32_t caller_uid;
    uint64_t attempted_value;
    uint32_t ifindex;
    uint32_t verdict;
    char     comm[16];
};

static struct {
    int          initialized;

    /* fds (持有期间一直 open) */
    int          fd_ctrl_map;
    int          fd_ringbuf_map;
    int          fd_lsm_prog;
    int          fd_lsm_link;
    int          fd_target_limit_map;   /* 我们打开的 limit_map fd */

    /* ringbuf consumer 线程 */
    pthread_t    rb_thread;
    int          rb_thread_started;
    int          rb_should_stop;
    void        *rb_data;               /* mmap'd ringbuf data area */
    size_t       rb_data_size;
    void        *rb_consumer_pos_page;  /* mmap'd consumer pos page */
    void        *rb_producer_pos_page;  /* mmap'd producer pos page */

    /* status (静态初始化 mutex, 任何调用顺序安全)
     * 之前用 pthread_mutex_init 在 hnc_lsm_init 里 dynamic init,
     * 但 set_fail / get_status 可能在 init 失败的早期就被调用,
     * 此时 dynamic init 已完成但调用栈复杂, NDK clang 编出的
     * pthread_mutex_lock 路径在 ARM64 上跟 host 行为不一致, 容易段错.
     * 改为 PTHREAD_MUTEX_INITIALIZER 一次性安全。 */
    pthread_mutex_t stat_lock;
    hnc_lsm_status_t stat;
} g = {
    .fd_ctrl_map = -1,
    .fd_ringbuf_map = -1,
    .fd_lsm_prog = -1,
    .fd_lsm_link = -1,
    .fd_target_limit_map = -1,
    .stat_lock = PTHREAD_MUTEX_INITIALIZER,
};

/* ══════════════════════════════════════════════════════════
 * 工具
 * ══════════════════════════════════════════════════════════ */

static void set_fail(const char *fmt, ...)
{
    /* 先把 fail_reason 拼到本地 buf, 再写共享状态 + 打印
     * 避免 va_start/va_end 在持锁中段错时无 log */
    char tmp[128];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    /* 先打日志, 即便 mutex 段错也能看到原因 */
    fprintf(stderr, "[lsm] FAIL: %s\n", tmp);
    fflush(stderr);
    pthread_mutex_lock(&g.stat_lock);
    g.stat.state = HNC_LSM_FAILED;
    snprintf(g.stat.fail_reason, sizeof(g.stat.fail_reason), "%s", tmp);
    pthread_mutex_unlock(&g.stat_lock);
}

#include <stdarg.h>

/* 检查 /sys/kernel/security/lsm 是否含 "bpf"
 * 返 1 = ok, 0 = no, -1 = 文件不可读 (可能 securityfs 没挂)
 */
static int probe_bpf_lsm_active(void)
{
    FILE *f = fopen("/sys/kernel/security/lsm", "r");
    if (!f) return -1;
    char buf[256] = {0};
    fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    return strstr(buf, "bpf") != NULL ? 1 : 0;
}

/* 读 vmlinux BTF, 找 "security_bpf" 的 BTF id (LSM hook 函数名)
 *
 * 简化做法: BPF_BTF_LOAD 不能直接拿 vmlinux 的 id, 要用 BPF_BTF_GET_FD_BY_ID
 * 遍历. 这里走更直接的路径: 用 bpf_obj_get_info 看不到 vmlinux btf_id,
 * 只能用 libbpf 的 btf__find_by_name. 我们手撸的话, 读
 * /sys/kernel/btf/vmlinux 解析 BTF blob, 自己找 FUNC 名为 "bpf" 的 LSM hook.
 *
 * Linux 5.11+ kernel 自动识别: 如果 prog->attach_btf_id == 0 且
 * expected_attach_type == BPF_LSM_MAC, kernel 会根据 prog 的 SEC name
 * ("lsm/bpf") 自己找. 但实测某些版本要求显式设 attach_btf_id, 失败时
 * 报 EINVAL.
 *
 * 当前实现: 让用户态自己读 vmlinux BTF 找 id. */

/* ── BTF lookup ────────────────────────────────────────────
 *
 * 历史方案: 自己解析 /sys/kernel/btf/vmlinux 找 security hook 的
 * BTF id, 但手撸 BTF parser 易越界 (vmlinux ~6MB, 千万 type entry,
 * 任何 kind padding 算错都会让后续 name_off 飞天导致 strcmp segfault).
 *
 * 当前方案: Linux 5.11+ 起, BPF_PROG_LOAD with attach_btf_id=0 +
 * expected_attach_type=BPF_LSM_MAC + 正确 prog_btf_fd, kernel 会读
 * prog 自己的 BTF 找 BTF_KIND_DECL_TAG 标记的 hook 名 ("lsm/bpf"),
 * 自动解析为 vmlinux 里的 security_bpf BTF id.
 *
 * 我们的 .bpf.c 里 SEC("lsm/bpf") 配合 clang 自动生成的 DECL_TAG,
 * 已经满足这个要求, 不需用户态干预.
 */


/* ══════════════════════════════════════════════════════════
 * BPF object 加载
 *
 * 简化: 我们的 .bpf.o ELF 结构非常固定 (单 prog + 2 maps + BTF).
 * 不通用 — 假定 sections 顺序与 hnc_limit_map_guard.bpf.o 一致。
 * ══════════════════════════════════════════════════════════ */

/* 创建 ARRAY map (ctrl) */
static int create_ctrl_map(void)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.map_type    = BPF_MAP_TYPE_ARRAY;
    attr.key_size    = 4;
    attr.value_size  = sizeof(struct hnc_lsm_ctrl_v);
    attr.max_entries = 1;
    strncpy(attr.map_name, "hnc_ctrl", sizeof(attr.map_name) - 1);
    long fd = sys_bpf(BPF_MAP_CREATE, &attr, sizeof(attr));
    return (int)fd;
}

/* 创建 RINGBUF map */
static int create_ringbuf_map(uint32_t bytes)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.map_type    = BPF_MAP_TYPE_RINGBUF;
    attr.key_size    = 0;     /* ringbuf 不用 */
    attr.value_size  = 0;
    attr.max_entries = bytes;
    strncpy(attr.map_name, "hnc_events", sizeof(attr.map_name) - 1);
    long fd = sys_bpf(BPF_MAP_CREATE, &attr, sizeof(attr));
    return (int)fd;
}

/* 解析 .bpf.o, 返回:
 *   - prog 指令数组 + 数量 (caller free)
 *   - .BTF section 内容 (caller free)
 *   - 重定位信息: prog 中哪些指令引用了哪个 map
 *
 * 简化: 假定单 prog, 2 maps. 不处理 multi-prog.
 *
 * 输出参数 prog_insns / prog_ninsn / btf_data / btf_size / map_relocs
 * map_relocs 数组: 每元素 = {insn_idx, map_idx (0=ctrl, 1=ringbuf)}
 */
struct map_reloc {
    uint32_t insn_idx;
    uint32_t map_idx;
};

static int parse_bpf_object(const char *path,
                            struct bpf_insn **prog_insns_out,
                            uint32_t *prog_ninsn_out,
                            void **btf_data_out,
                            uint32_t *btf_size_out,
                            struct map_reloc **relocs_out,
                            uint32_t *nrelocs_out,
                            char *map_names_out[2])
{
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -errno;
    struct stat st;
    if (fstat(fd, &st) != 0) { close(fd); return -errno; }
    void *elf = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (elf == MAP_FAILED) return -errno;

    /* ELF64 header */
    Elf64_Ehdr *eh = (Elf64_Ehdr *)elf;
    if (memcmp(eh->e_ident, "\x7f""ELF", 4) != 0 || eh->e_ident[4] != 2 /* ELF64 */) {
        munmap(elf, st.st_size); return -EINVAL;
    }

    Elf64_Shdr *sh = (Elf64_Shdr *)((char *)elf + eh->e_shoff);
    const char *shstrtab = (const char *)elf + sh[eh->e_shstrndx].sh_offset;

    /* 找 sections: lsm/bpf, .maps, .BTF, .rellsm/bpf, .symtab, .strtab */
    Elf64_Shdr *sh_prog = NULL, *sh_btf = NULL;
    Elf64_Shdr *sh_relprog = NULL, *sh_symtab = NULL, *sh_strtab = NULL;

    for (uint16_t i = 0; i < eh->e_shnum; i++) {
        const char *name = shstrtab + sh[i].sh_name;
        if (strcmp(name, "lsm/bpf") == 0)        sh_prog = &sh[i];
        else if (strcmp(name, ".BTF") == 0)      sh_btf = &sh[i];
        else if (strcmp(name, ".rellsm/bpf") == 0) sh_relprog = &sh[i];
        else if (strcmp(name, ".symtab") == 0)   sh_symtab = &sh[i];
        else if (strcmp(name, ".strtab") == 0)   sh_strtab = &sh[i];
    }
    if (!sh_prog || !sh_btf || !sh_symtab || !sh_strtab) {
        fprintf(stderr, "[lsm] missing required ELF section\n");
        munmap(elf, st.st_size); return -EINVAL;
    }

    /* 拷 prog insns */
    uint32_t ninsn = sh_prog->sh_size / sizeof(struct bpf_insn);
    struct bpf_insn *insns = malloc(sh_prog->sh_size);
    if (!insns) { munmap(elf, st.st_size); return -ENOMEM; }
    memcpy(insns, (char *)elf + sh_prog->sh_offset, sh_prog->sh_size);

    /* 拷 BTF */
    void *btf_data = malloc(sh_btf->sh_size);
    if (!btf_data) { free(insns); munmap(elf, st.st_size); return -ENOMEM; }
    memcpy(btf_data, (char *)elf + sh_btf->sh_offset, sh_btf->sh_size);

    /* 解析 .symtab: 找 hnc_ctrl_map / hnc_lsm_events 的 symbol */
    Elf64_Sym *symtab = (Elf64_Sym *)((char *)elf + sh_symtab->sh_offset);
    uint32_t nsyms = sh_symtab->sh_size / sizeof(Elf64_Sym);
    const char *strtab = (const char *)elf + sh_strtab->sh_offset;

    /* map names → symbol idx (用于 reloc 反查) */
    int sym_ctrl_idx = -1, sym_ringbuf_idx = -1;
    for (uint32_t i = 0; i < nsyms; i++) {
        const char *n = strtab + symtab[i].st_name;
        if (strcmp(n, "hnc_ctrl_map") == 0)    sym_ctrl_idx = (int)i;
        else if (strcmp(n, "hnc_lsm_events") == 0) sym_ringbuf_idx = (int)i;
    }
    map_names_out[0] = strdup("hnc_ctrl_map");
    map_names_out[1] = strdup("hnc_lsm_events");

    /* 解析 .rellsm/bpf 重定位 */
    uint32_t nrelocs = 0;
    struct map_reloc *relocs = NULL;
    if (sh_relprog) {
        uint32_t nrel = sh_relprog->sh_size / sizeof(Elf64_Rel);
        Elf64_Rel *rels = (Elf64_Rel *)((char *)elf + sh_relprog->sh_offset);
        relocs = calloc(nrel, sizeof(*relocs));
        if (!relocs) {
            free(insns); free(btf_data); munmap(elf, st.st_size); return -ENOMEM;
        }
        for (uint32_t i = 0; i < nrel; i++) {
            uint32_t sym_idx = ELF64_R_SYM(rels[i].r_info);
            uint32_t insn_idx = rels[i].r_offset / sizeof(struct bpf_insn);
            int mi = -1;
            if ((int)sym_idx == sym_ctrl_idx)    mi = 0;
            else if ((int)sym_idx == sym_ringbuf_idx) mi = 1;
            else continue;
            relocs[nrelocs].insn_idx = insn_idx;
            relocs[nrelocs].map_idx  = mi;
            nrelocs++;
        }
    }

    /* v5.0.0-beta.4 hotfix3: 必须在 munmap 之前把 sh_btf->sh_size 取出来,
     * 否则 munmap 释放 ELF 映射后 sh_btf 指针变野指针, 解引用 SEGV.
     * (致谢 evaluation AI 的 root cause 分析:
     *  fault addr = mmap_base + e_shoff + 7*sizeof(Shdr) + offsetof(sh_size)
     *  对应 [.BTF section header].sh_size 字段,
     *  落在 munmap 释放后变成 PROT_NONE 的"洞", tombstone 误识为 guard page) */
    uint32_t btf_size_local = sh_btf->sh_size;

    munmap(elf, st.st_size);

    *prog_insns_out  = insns;
    *prog_ninsn_out  = ninsn;
    *btf_data_out    = btf_data;
    *btf_size_out    = btf_size_local;   /* 安全: 不再触碰已释放的 mmap 区 */
    *relocs_out      = relocs;
    *nrelocs_out     = nrelocs;
    return 0;
}

/* fixup map fd 到 prog insns
 * BPF instr: 64-bit ld_imm64, src=BPF_PSEUDO_MAP_FD, imm=map_fd */
static void fixup_map_fds(struct bpf_insn *insns, uint32_t ninsn,
                          struct map_reloc *relocs, uint32_t nrelocs,
                          int map_fds[2])
{
    (void)ninsn;
    for (uint32_t i = 0; i < nrelocs; i++) {
        struct bpf_insn *ins = &insns[relocs[i].insn_idx];
        ins->src_reg = 1;     /* BPF_PSEUDO_MAP_FD */
        ins->imm     = map_fds[relocs[i].map_idx];
    }
}

/* BPF_BTF_LOAD: 把 BTF blob 注入 kernel, 拿到 btf fd
 * v5.0.0-beta.4 hotfix4: 加 log_buf 让 kernel 报详细 BTF 校验失败原因 */
static int load_btf(const void *btf_data, uint32_t btf_size,
                    char *log_buf, uint32_t log_buf_size)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.btf      = (uint64_t)(uintptr_t)btf_data;
    attr.btf_size = btf_size;
    if (log_buf && log_buf_size) {
        attr.btf_log_buf  = (uint64_t)(uintptr_t)log_buf;
        attr.btf_log_size = log_buf_size;
        attr.btf_log_level = 1;
        log_buf[0] = 0;
    }
    long fd = sys_bpf(BPF_BTF_LOAD, &attr, sizeof(attr));
    return (int)fd;
}

/* BPF_PROG_LOAD: 加载 LSM 程序 */
static int load_lsm_prog(const struct bpf_insn *insns, uint32_t ninsn,
                          int btf_fd, int attach_btf_id,
                          char *log_buf, size_t log_buf_size)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.prog_type           = BPF_PROG_TYPE_LSM;
    attr.expected_attach_type= BPF_LSM_MAC;
    attr.insn_cnt            = ninsn;
    attr.insns               = (uint64_t)(uintptr_t)insns;
    attr.license             = (uint64_t)(uintptr_t)"GPL";
    attr.attach_btf_id       = attach_btf_id;
    attr.prog_btf_fd         = btf_fd;
    if (log_buf && log_buf_size) {
        attr.log_level  = 1;
        attr.log_buf    = (uint64_t)(uintptr_t)log_buf;
        attr.log_size   = log_buf_size;
    }
    strncpy(attr.prog_name, "hnc_lsm_grd", sizeof(attr.prog_name) - 1);
    long fd = sys_bpf(BPF_PROG_LOAD, &attr, sizeof(attr));
    return (int)fd;
}

/* BPF_RAW_TRACEPOINT_OPEN attach to LSM hook
 * 对于 LSM, target_fd 应该是 0 (不需要 cgroup), name 也不用,
 * 直接靠 prog 自身的 attach_btf_id 决定 hook 位置 */
static int attach_lsm(int prog_fd)
{
    union bpf_attr attr;
    memset(&attr, 0, sizeof(attr));
    attr.raw_tracepoint.name    = 0;
    attr.raw_tracepoint.prog_fd = (uint32_t)prog_fd;
    long fd = sys_bpf(BPF_RAW_TRACEPOINT_OPEN, &attr, sizeof(attr));
    return (int)fd;
}

/* ══════════════════════════════════════════════════════════
 * Ringbuf 消费 (epoll + 解析事件)
 *
 * 不依赖 libbpf 的 ring_buffer__poll, 自己 mmap + 解析。
 * Ringbuf 内存布局 (kernel uapi/linux/bpf.h):
 *   - 第一页: consumer_pos
 *   - 第二页: producer_pos
 *   - 数据区: 2 倍 max_entries (双映射) 或单映射 max_entries
 * 简化: 单映射 + 不用 epoll wakeup, 用 epoll_wait 100ms 轮询
 * ══════════════════════════════════════════════════════════ */

#define BPF_RINGBUF_BUSY_BIT     (1U << 31)
#define BPF_RINGBUF_DISCARD_BIT  (1U << 30)
#define BPF_RINGBUF_HDR_SZ        8

static void ringbuf_handle_event(const void *data, size_t len)
{
    if (len < sizeof(struct hnc_lsm_event_v)) return;
    const struct hnc_lsm_event_v *ev = (const struct hnc_lsm_event_v *)data;

    pthread_mutex_lock(&g.stat_lock);
    if (ev->verdict)
        g.stat.deny_count++;
    else
        g.stat.allow_count++;
    g.stat.last_event_ts = (int64_t)time(NULL);
    snprintf(g.stat.last_caller_comm, sizeof(g.stat.last_caller_comm),
             "%s", ev->comm);
    pthread_mutex_unlock(&g.stat_lock);

    if (ev->verdict) {
        fprintf(stderr,
                "[lsm] DENY: comm=%s pid=%u uid=%u ifindex=%u val=0x%llx\n",
                ev->comm, ev->caller_pid, ev->caller_uid,
                ev->ifindex, (unsigned long long)ev->attempted_value);
    }
}

static void *ringbuf_thread(void *arg)
{
    (void)arg;
    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) return NULL;
    struct epoll_event ev = { .events = EPOLLIN, .data.fd = g.fd_ringbuf_map };
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, g.fd_ringbuf_map, &ev) != 0) {
        close(epfd); return NULL;
    }

    while (!g.rb_should_stop) {
        struct epoll_event ev2;
        int n = epoll_wait(epfd, &ev2, 1, 200);   /* 200ms timeout */
        if (n <= 0) continue;

        /* drain ringbuf
         * consumer_pos 在 page 0 第 0 个 u64
         * producer_pos 在 page 1 第 0 个 u64
         * data 在 page 2 起 g.rb_data_size bytes (mod size 形成环) */
        volatile uint64_t *cons = (uint64_t *)g.rb_consumer_pos_page;
        volatile uint64_t *prod = (uint64_t *)g.rb_producer_pos_page;
        uint64_t cpos = *cons;
        uint64_t ppos = *prod;
        __sync_synchronize();

        while (cpos < ppos) {
            uint32_t *hdr = (uint32_t *)((char *)g.rb_data + (cpos & (g.rb_data_size - 1)));
            uint32_t len = hdr[0];
            if (len & BPF_RINGBUF_BUSY_BIT) break;   /* producer 还没写完 */

            uint32_t real_len = len & ~(BPF_RINGBUF_BUSY_BIT | BPF_RINGBUF_DISCARD_BIT);
            uint32_t round_len = (real_len + 7) & ~7U;

            if (!(len & BPF_RINGBUF_DISCARD_BIT)) {
                void *evdata = (char *)hdr + BPF_RINGBUF_HDR_SZ;
                ringbuf_handle_event(evdata, real_len);
            }
            cpos += BPF_RINGBUF_HDR_SZ + round_len;
            __sync_synchronize();
            *cons = cpos;
        }
    }

    close(epfd);
    return NULL;
}

/* ══════════════════════════════════════════════════════════
 * Public API
 * ══════════════════════════════════════════════════════════ */

int hnc_lsm_init(const char *bpf_object_path,
                 const char *target_limit_map_path,
                 uint32_t initial_ifindex)
{
    if (g.initialized) return 0;
    /* mutex 已 PTHREAD_MUTEX_INITIALIZER 静态初始化, 无需 dynamic init */
    g.stat.state = HNC_LSM_DISABLED;
    g.stat.hotspotd_pid = (uint32_t)getpid();

    /* ─── Step 1: 检测 BPF LSM 可用 ─────────────────────────── */
    int rc = probe_bpf_lsm_active();
    if (rc < 0) {
        /* securityfs 没挂, 我们自己挂上 */
        if (mount("none", "/sys/kernel/security", "securityfs", 0, NULL) != 0
            && errno != EBUSY) {
            set_fail("securityfs mount: %s", strerror(errno));
            return -2;
        }
        rc = probe_bpf_lsm_active();
    }
    if (rc != 1) {
        set_fail("BPF LSM not in /sys/kernel/security/lsm");
        return -2;
    }
    fprintf(stderr, "[lsm] BPF LSM active in kernel\n");

    /* ─── Step 2: 拿目标 limit_map 的 map_id ──────────────── */
    {
        union bpf_attr a;
        memset(&a, 0, sizeof(a));
        a.pathname = (uint64_t)(uintptr_t)target_limit_map_path;
        long fd = sys_bpf(BPF_OBJ_GET, &a, sizeof(a));
        if (fd < 0) {
            set_fail("bpf_obj_get(%s): %s", target_limit_map_path, strerror(errno));
            return -1;
        }
        g.fd_target_limit_map = (int)fd;

        struct bpf_map_info info;
        memset(&info, 0, sizeof(info));
        uint32_t info_len = sizeof(info);
        union bpf_attr a2;
        memset(&a2, 0, sizeof(a2));
        a2.info.bpf_fd = (uint32_t)fd;
        a2.info.info_len = info_len;
        a2.info.info = (uint64_t)(uintptr_t)&info;
        if (sys_bpf(BPF_OBJ_GET_INFO_BY_FD, &a2, sizeof(a2)) < 0) {
            set_fail("get_info_by_fd: %s", strerror(errno));
            return -1;
        }
        pthread_mutex_lock(&g.stat_lock);
        g.stat.protected_map_id = info.id;
        g.stat.protected_ifindex = initial_ifindex;
        pthread_mutex_unlock(&g.stat_lock);
        fprintf(stderr, "[lsm] target limit_map id=%u\n", info.id);
        fflush(stderr);
    }

    /* ─── Step 3: 创建我们的 maps ─────────────────────────── */
    fprintf(stderr, "[lsm] step3: create_ctrl_map\n"); fflush(stderr);
    g.fd_ctrl_map = create_ctrl_map();
    if (g.fd_ctrl_map < 0) {
        set_fail("create_ctrl_map: %s", strerror(errno));
        return -1;
    }
    fprintf(stderr, "[lsm] step3: ctrl_map fd=%d\n", g.fd_ctrl_map); fflush(stderr);

    g.fd_ringbuf_map = create_ringbuf_map(64 * 1024);
    if (g.fd_ringbuf_map < 0) {
        set_fail("create_ringbuf_map: %s", strerror(errno));
        return -1;
    }
    fprintf(stderr, "[lsm] step3: ringbuf_map fd=%d\n", g.fd_ringbuf_map); fflush(stderr);

    /* ─── Step 4: 解析 .bpf.o ─────────────────────────────── */
    fprintf(stderr, "[lsm] step4: parse_bpf_object\n"); fflush(stderr);
    struct bpf_insn *insns = NULL;
    uint32_t ninsn = 0;
    void *btf_data = NULL;
    uint32_t btf_size = 0;
    struct map_reloc *relocs = NULL;
    uint32_t nrelocs = 0;
    char *map_names[2] = {0};
    rc = parse_bpf_object(bpf_object_path,
                          &insns, &ninsn,
                          &btf_data, &btf_size,
                          &relocs, &nrelocs,
                          map_names);
    if (rc < 0) {
        set_fail("parse_bpf_object(%s): %s", bpf_object_path, strerror(-rc));
        return -1;
    }
    fprintf(stderr, "[lsm] step4: parsed bpf.o: %u insns, %u relocs, btf=%u bytes\n",
            ninsn, nrelocs, btf_size);
    fflush(stderr);

    /* fixup map fds */
    int map_fds[2] = { g.fd_ctrl_map, g.fd_ringbuf_map };
    fixup_map_fds(insns, ninsn, relocs, nrelocs, map_fds);

    /* ─── Step 5: attach_btf_id 由 kernel 自动推断 (Linux 5.11+) ─── */
    int sec_bpf_btf_id = 0;
    fprintf(stderr, "[lsm] step5: using attach_btf_id=0 (kernel auto-infer)\n");
    fflush(stderr);

    /* ─── Step 6: BPF_BTF_LOAD prog btf ────────────────────── */
    fprintf(stderr, "[lsm] step6: BPF_BTF_LOAD\n"); fflush(stderr);
    static char btf_log_buf[16 * 1024];
    int prog_btf_fd = load_btf(btf_data, btf_size, btf_log_buf, sizeof(btf_log_buf));
    if (prog_btf_fd < 0) {
        if (btf_log_buf[0]) {
            fprintf(stderr, "[lsm] BTF verifier log:\n%s\n", btf_log_buf);
            fflush(stderr);
        }
        set_fail("BPF_BTF_LOAD: %s", strerror(errno));
        free(insns); free(btf_data); free(relocs);
        return -1;
    }
    fprintf(stderr, "[lsm] step6: prog_btf_fd=%d\n", prog_btf_fd); fflush(stderr);

    /* ─── Step 7: BPF_PROG_LOAD ────────────────────────────── */
    fprintf(stderr, "[lsm] step7: BPF_PROG_LOAD\n"); fflush(stderr);
    static char log_buf[64 * 1024];
    log_buf[0] = 0;
    int prog_fd = load_lsm_prog(insns, ninsn, prog_btf_fd, sec_bpf_btf_id,
                                 log_buf, sizeof(log_buf));
    int load_errno = errno;
    free(insns); free(btf_data); free(relocs);
    close(prog_btf_fd);
    if (prog_fd < 0) {
        if (log_buf[0]) {
            fprintf(stderr, "[lsm] verifier log:\n%s\n", log_buf);
        }
        set_fail("BPF_PROG_LOAD (LSM): %s", strerror(load_errno));
        return -1;
    }
    g.fd_lsm_prog = prog_fd;
    fprintf(stderr, "[lsm] step7: LSM prog loaded, fd=%d\n", prog_fd);
    fflush(stderr);

    /* ─── Step 8: populate ctrl map ────────────────────────── */
    fprintf(stderr, "[lsm] step8: populate ctrl map\n"); fflush(stderr);
    {
        struct hnc_lsm_ctrl_v v = {
            .protected_map_id  = g.stat.protected_map_id,
            .protected_ifindex = initial_ifindex,
            .hotspotd_pid      = (uint32_t)getpid(),
            .enabled           = 1,
        };
        uint32_t k = 0;
        union bpf_attr a;
        memset(&a, 0, sizeof(a));
        a.map_fd = (uint32_t)g.fd_ctrl_map;
        a.key    = (uint64_t)(uintptr_t)&k;
        a.value  = (uint64_t)(uintptr_t)&v;
        a.flags  = 0;
        if (sys_bpf(BPF_MAP_UPDATE_ELEM, &a, sizeof(a)) < 0) {
            set_fail("populate ctrl: %s", strerror(errno));
            return -1;
        }
    }

    /* ─── Step 9: mmap ringbuf 数据区 ─────────────────────── */
    fprintf(stderr, "[lsm] step9: mmap ringbuf\n"); fflush(stderr);
    long page = sysconf(_SC_PAGESIZE);
    g.rb_data_size = 64 * 1024;
    g.rb_consumer_pos_page = mmap(NULL, page, PROT_READ | PROT_WRITE,
                                   MAP_SHARED, g.fd_ringbuf_map, 0);
    g.rb_producer_pos_page = mmap(NULL, page, PROT_READ,
                                   MAP_SHARED, g.fd_ringbuf_map, page);
    g.rb_data = mmap(NULL, g.rb_data_size * 2, PROT_READ,
                      MAP_SHARED, g.fd_ringbuf_map, page * 2);
    if (g.rb_consumer_pos_page == MAP_FAILED ||
        g.rb_producer_pos_page == MAP_FAILED ||
        g.rb_data == MAP_FAILED) {
        set_fail("ringbuf mmap: %s", strerror(errno));
        return -1;
    }
    fprintf(stderr, "[lsm] step9: mmap OK (cons=%p prod=%p data=%p)\n",
            g.rb_consumer_pos_page, g.rb_producer_pos_page, g.rb_data);
    fflush(stderr);

    /* ─── Step 10: attach LSM ─────────────────────────────── */
    fprintf(stderr, "[lsm] step10: attach LSM\n"); fflush(stderr);
    int link_fd = attach_lsm(prog_fd);
    if (link_fd < 0) {
        set_fail("attach_lsm: %s", strerror(errno));
        return -1;
    }
    g.fd_lsm_link = link_fd;
    fprintf(stderr, "[lsm] step10: link_fd=%d\n", link_fd); fflush(stderr);

    /* ─── Step 11: 启 ringbuf consumer 线程 ────────────────── */
    fprintf(stderr, "[lsm] step11: start ringbuf consumer thread\n"); fflush(stderr);
    g.rb_should_stop = 0;
    if (pthread_create(&g.rb_thread, NULL, ringbuf_thread, NULL) != 0) {
        fprintf(stderr, "[lsm] WARN: ringbuf thread start failed\n");
    } else {
        g.rb_thread_started = 1;
    }

    pthread_mutex_lock(&g.stat_lock);
    g.stat.state = HNC_LSM_ACTIVE;
    g.stat.fail_reason[0] = 0;
    pthread_mutex_unlock(&g.stat_lock);

    g.initialized = 1;
    fprintf(stderr, "[lsm] ACTIVE. protecting map_id=%u ifindex=%u, hotspotd_pid=%u\n",
            g.stat.protected_map_id, initial_ifindex, (uint32_t)getpid());
    fflush(stderr);
    return 0;
}

int hnc_lsm_update_ifindex(uint32_t new_ifindex)
{
    if (!g.initialized || g.fd_ctrl_map < 0) return -1;

    /* 读当前 ctrl, 改 ifindex 写回 */
    struct hnc_lsm_ctrl_v v;
    uint32_t k = 0;
    union bpf_attr a;
    memset(&a, 0, sizeof(a));
    a.map_fd = (uint32_t)g.fd_ctrl_map;
    a.key    = (uint64_t)(uintptr_t)&k;
    a.value  = (uint64_t)(uintptr_t)&v;
    if (sys_bpf(BPF_MAP_LOOKUP_ELEM, &a, sizeof(a)) < 0) return -1;

    v.protected_ifindex = new_ifindex;

    memset(&a, 0, sizeof(a));
    a.map_fd = (uint32_t)g.fd_ctrl_map;
    a.key    = (uint64_t)(uintptr_t)&k;
    a.value  = (uint64_t)(uintptr_t)&v;
    if (sys_bpf(BPF_MAP_UPDATE_ELEM, &a, sizeof(a)) < 0) return -1;

    pthread_mutex_lock(&g.stat_lock);
    g.stat.protected_ifindex = new_ifindex;
    pthread_mutex_unlock(&g.stat_lock);
    fprintf(stderr, "[lsm] ifindex updated to %u\n", new_ifindex);
    return 0;
}

void hnc_lsm_shutdown(void)
{
    if (!g.initialized) return;

    g.rb_should_stop = 1;
    if (g.rb_thread_started) {
        pthread_join(g.rb_thread, NULL);
        g.rb_thread_started = 0;
    }

    if (g.fd_lsm_link >= 0) close(g.fd_lsm_link);
    if (g.fd_lsm_prog >= 0) close(g.fd_lsm_prog);
    if (g.fd_ctrl_map >= 0) close(g.fd_ctrl_map);
    if (g.fd_ringbuf_map >= 0) close(g.fd_ringbuf_map);
    if (g.fd_target_limit_map >= 0) close(g.fd_target_limit_map);

    long page = sysconf(_SC_PAGESIZE);
    if (g.rb_data && g.rb_data != MAP_FAILED) munmap(g.rb_data, g.rb_data_size * 2);
    if (g.rb_consumer_pos_page && g.rb_consumer_pos_page != MAP_FAILED)
        munmap(g.rb_consumer_pos_page, page);
    if (g.rb_producer_pos_page && g.rb_producer_pos_page != MAP_FAILED)
        munmap(g.rb_producer_pos_page, page);

    pthread_mutex_destroy(&g.stat_lock);
    /* 注: PTHREAD_MUTEX_INITIALIZER 静态 mutex destroy 后再次 lock 是 UB,
     * 但 hotspotd shutdown 后整个进程退出, 不会再调 get_status, 安全. */
    g.initialized = 0;
    fprintf(stderr, "[lsm] shutdown complete\n");
}

void hnc_lsm_get_status(hnc_lsm_status_t *out)
{
    if (!out) return;
    pthread_mutex_lock(&g.stat_lock);
    *out = g.stat;
    pthread_mutex_unlock(&g.stat_lock);
}

int hnc_lsm_status_to_json_fragment(const hnc_lsm_status_t *st,
                                     char *buf, size_t buf_size)
{
    if (!st || !buf) return -1;
    const char *state_str =
        (st->state == HNC_LSM_ACTIVE)   ? "active"   :
        (st->state == HNC_LSM_FAILED)   ? "failed"   :
        (st->state == HNC_LSM_DISABLED) ? "disabled" : "unknown";

    int n = snprintf(buf, buf_size,
        "\"lsm\":{"
        "\"state\":\"%s\","
        "\"protected_map_id\":%u,"
        "\"protected_ifindex\":%u,"
        "\"hotspotd_pid\":%u,"
        "\"deny_count\":%llu,"
        "\"allow_count\":%llu,"
        "\"last_event_ts\":%lld,"
        "\"last_caller\":\"%s\","
        "\"fail_reason\":\"%s\""
        "}",
        state_str,
        st->protected_map_id,
        st->protected_ifindex,
        st->hotspotd_pid,
        (unsigned long long)st->deny_count,
        (unsigned long long)st->allow_count,
        (long long)st->last_event_ts,
        st->last_caller_comm,
        st->fail_reason);

    if (n < 0 || (size_t)n >= buf_size) return -1;
    return n;
}
