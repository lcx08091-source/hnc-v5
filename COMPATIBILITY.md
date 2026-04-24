# HNC 兼容性矩阵

**图例**:
- ✅ 工作
- ⚠️ 工作但有限制(见备注)
- ❌ 不工作
- ❓ 未测试

---

## 确认工作

| ROM | 设备 | Android | 内核 | Root | 热点 iface | 下行限速 | 上行限速 | BPF LSM | 自愈 tc | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|
| **ColorOS 16** | realme GT 7 Pro (RMX5010) | 16 | 6.6.102 | SukiSU Ultra | wlan2 | ✅ | ✅ | ❓ kprobe 未证实 | ✅ | 主测设备,限速/自愈全功能。BPF LSM guard 在 ColorOS 上实际 attach 状态待核(`/sys/kernel/security/lsm` 是否含 `bpf`)。主路径不依赖 guard,guard 只在 framework BPF offload 触发时起作用,日常使用无感。|

---

## 待测 / 报告中

| ROM | 设备 | 状态 | Issue |
|---|---|---|---|
| HyperOS 2 | 小米/红米 | ❓ 待测 | - |
| OneUI 7 | 三星 Galaxy | ❓ 待测 | - |
| OriginOS 5 | vivo/iQOO | ❓ 待测 | - |
| OxygenOS 15 | 一加 | ❓ 待测(架构相同 ColorOS,应该可用) | - |
| Pixel 原生 16 | Pixel 9 | ❓ 待测 | - |
| LineageOS 22 | 通用 | ❓ 待测 | - |

---

## 怎么报告你的测试结果

装上后跑一次诊断:

```sh
su -c 'sh /data/local/hnc/bin/diag.sh' > /sdcard/hnc_diag.txt
```

开一个 issue,标题写 `[Compatibility] <ROM 名> <设备型号>`,附上 `hnc_diag.txt` 和以下信息:

- **热点 iface 名字**: `ip link show | grep -E "wlan|ap|softap" | awk '{print $2}'`
- **能否下行限速到 1 MB/s**(连一台手机/电脑测速)
- **能否上行限速到 1 MB/s**
- **内核是否支持 BPF LSM**: `cat /sys/kernel/security/lsm`(grep `bpf`)
- **是否支持 kprobe**: `[ -e /sys/kernel/tracing/kprobe_events ]`

---

## 已知限制

| ROM 系 | 问题 | 缓解 |
|---|---|---|
| ColorOS / OxygenOS | `oplus_netd` 主动清外部 tc 规则 | HNC 自愈已覆盖 |
| MIUI 14+ | (待确认) `miui_net_*` 服务 | ? |
| 老旧 AOSP(Android < 13)| 无 BPF tethering offload | 上行限速走兜底路径,精度下降 |
| iOS 客户端 | "私有 WiFi 地址" 每次随机 MAC | 关掉此功能;或认命每次重配 |
