# HNC v5.1.0-rc1 hotfix17.5

## 目标

在 MIUI/Android Wi-Fi 热点只能使用 root HTB fallback、无法挂载最精确队列链路时，提供“精确模式 / 兼容模式”切换。

## 改动

- WebUI：仅在 root HTB fallback 场景显示“限速策略”切换面板。
  - 精确模式：更小 burst/cburst，让测速更接近设定值。
  - 兼容模式：保留较宽 burst，稳定性优先，允许短暂突发。
- WebUI：切换控件使用原有玻璃卡片、圆角分段按钮、蓝色渐变激活态，保持界面风格一致。
- tc_manager.sh：新增 `tc_qos_mode` 读取逻辑。
  - 支持 `precise` / `compat`。
  - 默认 `compat`，避免老设备升级后突然变激进。
- tc_manager.sh：root HTB fallback 成功时写入 `/data/local/hnc/run/tc_qos_fallback`，作为 WebUI 显示条件。
- capability_probe.sh：输出 `tc_qos_mode` 与 `qos_fallback_required`，给新版后端/WebUI 读取。

## 注意

- 该切换只在无法使用最精确队列链路、进入 root HTB fallback 时显示。
- 上行 IFB/mirred 不支持的设备仍然保持上行禁用。
- 精确模式不保证测速软件瞬时值完全等于设置值，但会降低 burst 导致的超速峰值。
