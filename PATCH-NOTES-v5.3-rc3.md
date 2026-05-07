# HNC v5.3.0-rc3 · Smart Queue 灰度增强

版本：v5.3.0-rc3
versionCode：530003

## 一句话总结

在 rc2 的 SQM 控制面基础上，补齐游戏/弱网预设、状态细化和一键灰度诊断，继续保持默认关闭，不改变旧版限速链路。

## 新增

- `sqm_manager.sh status` 升级为 `schema=2`：
  - `preset`
  - `preset_detail`
  - `presets`
  - `recommended_leaf`
  - `detected_leaf`
  - `reason`
  - `last_diag`
- `sqm_manager.sh` 新增预设命令：
  - `presets`
  - `get-preset`
  - `set-preset off|balanced|game|weaknet|poor|extreme|custom`
- 新增 `bin/sqm_gray_diag.sh`：
  - 生成 `/data/local/hnc/run/sqm_gray_diag/sqm_gray_diag-*.txt`
  - 记录版本、SQM 状态、capabilities、qdisc/class/filter、rules 摘要、sqm/tc 日志尾部、系统 hints
  - 对 MAC/IP 做基础脱敏
- `/api/action sqm_set` 新增 `preset` 参数。
- WebUI 设置页新增 SQM 预设按钮：均衡、游戏、弱网、较差。
- 设备卡新增“填入预设”按钮：把当前 SQM 预设的限速/延迟/抖动/丢包数值填到输入框，用户确认后再点应用。

## 安全边界

- 弱网预设不会全局直接制造丢包。
- 预设只保存状态，并在设备卡上作为填表助手使用。
- 真实 delay/jitter/loss 仍由 netem 接管。
- 不接管 ColorOS/Android 系统 BPF。
- 不依赖 nftables。

## 测试

新增：

- `test/unit/test_sqm_v53_rc3.sh`

覆盖：

- `sqm_manager.sh status` 输出 schema 2、预设数组、detected leaf。
- `set-preset weaknet` 正确持久化 preset/mode/profile。
- WebUI 包含弱网预设、填入预设按钮、SQM 诊断按钮。
- Go `sqm_set` action 接收 preset 参数并调用 `set-preset`。
