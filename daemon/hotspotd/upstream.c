/* upstream.c — HNC v5.0 alpha.2 上游 ifindex 探测实现
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
#include <ctype.h>
#include <unistd.h>

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
 * 入口
 * ══════════════════════════════════════════════════════════ */

int upstream_detect_primary(int *ifindex_out,
                             char *ifname_out,
                             size_t ifname_size)
{
    if (upstream_detect_via_ip_route(ifindex_out, ifname_out, ifname_size) == 0) {
        return 0;
    }
    if (upstream_detect_via_proc_route(ifindex_out, ifname_out, ifname_size) == 0) {
        return 0;
    }
    /* Tier 3 (BPF upstream4_map 反查) 留 alpha.3 */
    return -1;
}
