# HNC v5.1.0-rc1 hotfix17.0

## 目标

hotfix17.0 是能力恢复路线的第一步：不直接改变限速/延迟策略，不强行启用 TBF/police，而是补齐安全、可重复的 tc 能力探测基础。

## 改动

- 新增 `bin/capability_probe.sh`。
- 使用临时 dummy 接口做沙盒探测，避免在真实热点接口 `wlan1/wlan2` 上破坏 qdisc。
- 生成 `/data/local/hnc/run/capabilities.json`，新增/细分字段：
  - `tc_binary`, `tc_binary_source`, `tc_version`, `tc_binary_ok`
  - `dummy_create`, `probe_iface`, `probe_iface_qdisc`
  - `tc_htb_supported`, `tc_tbf_supported`, `tc_netem_supported`
  - `tc_ingress_supported`, `tc_clsact_supported`
  - `tc_u32_supported`, `tc_flower_supported`, `tc_matchall_supported`
  - `tc_police_supported`, `tc_mirred_supported`, `ifb_supported`
  - `downlink_mode`, `uplink_mode`, `delay_mode`
- 保留兼容字段：`tc_htb`, `tc_netem`, `tc_ifb`, `tc_ifb_create`, `tc_mirred`, `tc_matchall`, `uplink_supported`。
- `service.sh` 已有启动钩子，会在开机时后台运行该探测脚本。

## 说明

- 本版不内置完整 iproute2 `tc`，但探测脚本会优先使用未来可加入的 `$HNC/bin/hnc_tc` 或 `$HNC/bin/tc`。
- 本版不启用 TBF 全局下行限速，也不启用 police 上行 fallback，只记录能力，为 hotfix17.1/17.2 做准备。
- 如果 dummy 接口无法创建，探测值会尽量保持 `null/unknown`，避免误把可用设备禁用。
