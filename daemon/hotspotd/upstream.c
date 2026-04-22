/* upstream.c — HNC v5.0 上游 ifindex 探测实现
 *
 * alpha.2: Tier 1 (ip route) + Tier 2 (/proc/net/route)
 * alpha.4 P0-C: + Tier 3 BPF upstream4_map 反查, 且 Tier 3 优先
 *
 * SPDX-License-Identifier: GPL-2.0
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "upstream.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <linux/bpf.h>

#include <net/if.h>

/* ══════════════════════════════════════════════════════════
 * Tier 1: popen "ip route get 8.8.8.8"
 *
 * 典型输出 (ColorOS 16 / RMX5010 实测):
 *   8.8.8.8 via 10.97.46.162 dev rmnet_data3 table rmnet_data3 src 10.97.46.161 uid 0
 *       cache mtu 1410
 *
 * 解析策略:
 *   找 " dev " 子串, 后面跟 iface name, 到下一个 space 结束
 *   if_nametoindex 转 ifindex, 失败 tier fail
 *
 * 为什么用 8.8.8.8 不用 1.1.1.1:
 *   - 两者都公网 anycast, 选路结果一致
 *   - 8.8.8.8 在中国大陆更可能被解析器/防火墙"假装可达", route 查询仍会返回正确出口
 *   - 实际上 `ip route get` 不发包, 只查内核路由表, 目标 IP 无需真正可达
 * ══════════════════════════════════════════════════════════ */

int upstream_detect_via_ip_route(int *ifindex_out,
                                  char *ifname_out,
                                  size_t ifname_size)
{
    if (!ifindex_out || !ifname_out || ifname_size < 2) return -1;

    FILE *f = popen("ip route get 8.8.8.8 2>/dev/null", "r");
    if (!f) return -1;

    char line[512];
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        /* 找 " dev " 子串 (两侧 space 防 "cache" 等误匹配) */
        const char *dev = strstr(line, " dev ");
        if (!dev) continue;
        dev += 5;   /* 跳过 " dev " */

        /* 提取 iface name (到下一个 whitespace 或 EOL) */
        char iface[IFNAMSIZ] = {0};
        int i = 0;
        while (dev[i] && !isspace((unsigned char)dev[i]) && i < (int)sizeof(iface) - 1) {
            iface[i] = dev[i];
            i++;
        }
        if (i == 0) continue;

        /* alpha.4: 过滤 VPN / tunnel 接口
         * 用户开 Clash / WireGuard / OpenVPN 时 ip route get 会返回 tun0/wg0
         * 这些不是物理上游, BPF upstream4_map 里没这 ifindex, disable 无效
         * 跳过继续 (但 popen 实际只返回一条, 所以这里会导致 Tier 1 返 -1, 触发 Tier 2/3) */
        if (strncmp(iface, "tun",  3) == 0 ||
            strncmp(iface, "tap",  3) == 0 ||
            strncmp(iface, "ppp",  3) == 0 ||
            strncmp(iface, "wg",   2) == 0 ||
            strncmp(iface, "gre",  3) == 0 ||
            strncmp(iface, "ipsec",5) == 0) {
            fprintf(stderr, "[upstream] Tier1: skipping VPN iface '%s'\n", iface);
            continue;
        }

        unsigned int idx = if_nametoindex(iface);
        if (idx == 0) continue;

        *ifindex_out = (int)idx;
        snprintf(ifname_out, ifname_size, "%s", iface);
        found = 1;
        break;
    }
    pclose(f);
    return found ? 0 : -1;
}

/* ══════════════════════════════════════════════════════════
 * Tier 2: /proc/net/route 扫描 (放宽条件)
 *
 * 与 alpha.1 的 detect_primary_upstream 区别:
 *   - alpha.1 只认 Destination=00000000 (default route)
 *   - alpha.2 放宽: 任何 RTF_UP 且 iface 名以 rmnet/wwan/eth/wlan/ppp 开头的
 *     第一条, 作为 "cellular/wan uplink" 启发式
 *
 * 这样即使 main table 没 default route, 也能从某个网段路由反推出 uplink iface。
 * 不如 Tier 1 准, 但优于直接失败。
 *
 * 注意: 我们跳过 wlan2 (手机热点 downstream), 只取可能的 uplink。
 * ══════════════════════════════════════════════════════════ */

static int looks_like_uplink_iface(const char *name)
{
    if (!name) return 0;
    /* 已知热点 downstream 名字, 排除 */
    if (strncmp(name, "wlan2", 5) == 0) return 0;
    if (strncmp(name, "ap",    2) == 0) return 0;
    if (strncmp(name, "swlan", 5) == 0) return 0;

    /* 可能 uplink 前缀 */
    if (strncmp(name, "rmnet", 5) == 0) return 1;
    if (strncmp(name, "wwan",  4) == 0) return 1;
    if (strncmp(name, "eth",   3) == 0) return 1;
    if (strncmp(name, "ppp",   3) == 0) return 1;
    /* Wi-Fi 上行 (手机当 STA 接其他 Wi-Fi, 罕见但存在) */
    if (strncmp(name, "wlan0", 5) == 0) return 1;
    if (strncmp(name, "wlan1", 5) == 0) return 1;
    return 0;
}

int upstream_detect_via_proc_route(int *ifindex_out,
                                    char *ifname_out,
                                    size_t ifname_size)
{
    if (!ifindex_out || !ifname_out || ifname_size < 2) return -1;

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
        char iface[IFNAMSIZ];
        char dest[16];
        unsigned int flags;
        if (sscanf(line, "%15s %15s %*s %x", iface, dest, &flags) != 3)
            continue;
        if (!(flags & 0x1)) continue;   /* RTF_UP */
        if (!looks_like_uplink_iface(iface)) continue;

        unsigned int idx = if_nametoindex(iface);
        if (idx == 0) continue;

        *ifindex_out = (int)idx;
        snprintf(ifname_out, ifname_size, "%s", iface);
        found = 1;
        break;
    }
    fclose(f);
    return found ? 0 : -1;
}

/* ══════════════════════════════════════════════════════════
 * Tier 3: BPF upstream4_map 反查 (alpha.4 P0-C)
 *
 * 原理:
 *   ColorOS 有 BPF tethering. 当有流量经过 HNC, upstream4_map 已被 Android
 *   framework 填满 (flow → upstream info). 每条 value[0] 就是真实物理上游
 *   ifindex.
 *
 * 为什么 Tier 3 要先行 (优先于 Tier 1/2):
 *   1. 最准确: BPF map 里就是 framework 认定的物理上游, 跟 HTB offload 用的是
 *      同一个 ifindex, 写 limit 必然命中
 *   2. 最可靠: hotspotd 本身已经打开 BPF (adapter_bpf), 同一 SELinux 上下文下
 *      读另一个 map 不会被挡; 而 popen("ip ...") 在 daemon domain 下
 *      可能被阻挡
 *   3. 免 VPN 干扰: tun0/wg0 不会出现在 tethering BPF map 里 (framework 只
 *      给 physical upstream 建 entry)
 *
 * 实现:
 *   - 打开 /sys/fs/bpf/tethering/map_offload_tether_upstream4_map
 *   - 用 BPF_MAP_GET_NEXT_KEY 枚举 (key=NULL → first)
 *   - 读 value, value[0] = upstream ifindex (AOSP TetherUpstream4Value struct)
 *   - if_indextoname 转 ifname
 *
 * Value 结构 (AOSP packages/modules/Connectivity/Tethering/bpf_progs/offload.h):
 *   struct TetherUpstream4Value {
 *       __u32 oif;           ← value[0], 本函数要的
 *       struct ethhdr macHeader;
 *       __u16 pmtu;
 *       ...
 *   };
 *   只要前 4 字节 u32, 不需完整 struct 对齐
 * ══════════════════════════════════════════════════════════ */

#define BPF_UPSTREAM4_MAP  "/sys/fs/bpf/tethering/map_offload_tether_upstream4_map"

static long _sys_bpf(enum bpf_cmd cmd, union bpf_attr *attr, unsigned int size)
{
    return syscall(__NR_bpf, cmd, attr, size);
}

int upstream_detect_via_bpf(int *ifindex_out,
                             char *ifname_out,
                             size_t ifname_size)
{
    if (!ifindex_out || !ifname_out || ifname_size < 2) return -1;

    /* 打开 upstream4_map */
    union bpf_attr oattr;
    memset(&oattr, 0, sizeof(oattr));
    oattr.pathname = (uint64_t)(uintptr_t)BPF_UPSTREAM4_MAP;
    long fd = _sys_bpf(BPF_OBJ_GET, &oattr, sizeof(oattr));
    if (fd < 0) {
        /* map 不存在 (ROM 没 tethering BPF) 或无权限 */
        fprintf(stderr, "[upstream] Tier3: open %s failed: %s\n",
                BPF_UPSTREAM4_MAP, strerror(errno));
        return -1;
    }

    /* key/value 尺寸不确定 (不同 ROM struct 略有差异), 用充足 buffer
     * 真实 TetherUpstream4Key ≈ 40 bytes, Value ≈ 24 bytes, 预留到 128 */
    unsigned char key[128];
    unsigned char value[128];
    memset(key, 0, sizeof(key));
    memset(value, 0, sizeof(value));

    /* 枚举第一个 key */
    union bpf_attr nattr;
    memset(&nattr, 0, sizeof(nattr));
    nattr.map_fd   = (uint32_t)fd;
    nattr.key      = 0;                   /* NULL = 取第一个 */
    nattr.next_key = (uint64_t)(uintptr_t)key;
    int rc = (int)_sys_bpf(BPF_MAP_GET_NEXT_KEY, &nattr, sizeof(nattr));
    if (rc < 0) {
        /* map 空 (还没流量经过 tethering BPF) 或 EOF */
        if (errno != ENOENT) {
            fprintf(stderr, "[upstream] Tier3: get_next_key failed: %s\n",
                    strerror(errno));
        } else {
            fprintf(stderr, "[upstream] Tier3: upstream4_map empty (no BPF offload flows yet)\n");
        }
        close(fd);
        return -1;
    }

    /* 用这个 key lookup value */
    union bpf_attr lattr;
    memset(&lattr, 0, sizeof(lattr));
    lattr.map_fd = (uint32_t)fd;
    lattr.key    = (uint64_t)(uintptr_t)key;
    lattr.value  = (uint64_t)(uintptr_t)value;
    rc = (int)_sys_bpf(BPF_MAP_LOOKUP_ELEM, &lattr, sizeof(lattr));
    close(fd);
    if (rc < 0) {
        fprintf(stderr, "[upstream] Tier3: lookup_elem failed: %s\n",
                strerror(errno));
        return -1;
    }

    /* value[0..3] = oif (upstream ifindex), little-endian */
    uint32_t oif = (uint32_t)value[0]
                 | ((uint32_t)value[1] << 8)
                 | ((uint32_t)value[2] << 16)
                 | ((uint32_t)value[3] << 24);
    if (oif == 0 || oif > 65535) {
        fprintf(stderr, "[upstream] Tier3: bogus oif=%u, skip\n", oif);
        return -1;
    }

    char name[IFNAMSIZ] = {0};
    if (if_indextoname(oif, name) == NULL) {
        fprintf(stderr, "[upstream] Tier3: if_indextoname(%u) failed\n", oif);
        return -1;
    }

    *ifindex_out = (int)oif;
    snprintf(ifname_out, ifname_size, "%s", name);
    fprintf(stderr, "[upstream] Tier3: found %s (ifindex=%d) via BPF upstream4_map\n",
            name, (int)oif);
    return 0;
}

/* ══════════════════════════════════════════════════════════
 * 入口: 优先级 Tier 3 > Tier 1 > Tier 2 (alpha.4)
 *
 * alpha.2 原顺序 Tier 1 → Tier 2. alpha.4 真机发现 Tier 1 在 VPN 场景下
 * 会返回 tun0 造成错配, 且 daemon SELinux 上下文可能阻挡 popen("ip").
 * BPF 反查最可靠, 提到最前.
 * ══════════════════════════════════════════════════════════ */

int upstream_detect_primary(int *ifindex_out,
                             char *ifname_out,
                             size_t ifname_size)
{
    /* Tier 3: BPF 反查 (最准, 最可靠) */
    if (upstream_detect_via_bpf(ifindex_out, ifname_out, ifname_size) == 0) {
        return 0;
    }
    /* Tier 1: ip route get (已过滤 VPN) */
    if (upstream_detect_via_ip_route(ifindex_out, ifname_out, ifname_size) == 0) {
        return 0;
    }
    /* Tier 2: /proc/net/route 启发式 (上面都失败才走) */
    if (upstream_detect_via_proc_route(ifindex_out, ifname_out, ifname_size) == 0) {
        return 0;
    }
    return -1;
}
