# HNC v5.2.0-rc1.10

## 目标

在 rc1.9 的“首屏后延迟自动 bridge”基础上，记住已经验证可用的 KSU/SukiSU bridge 传输方式，减少每次打开 WebUI 都先等待 HTTP 直连失败的延迟。

## 变更

- 成功自动 bridge 后，记录 `hnc.transport_hint.v1=bridge`。
- 成功手动“强制桥接”后，也记录 bridge 偏好。
- 下次打开 WebUI 时：
  - 仍先完成首屏渲染，避免白屏；
  - 若检测到 bridge 偏好，则跳过 HTTP 直连等待；
  - 首屏稳定后延迟约 320ms 自动尝试 bridge。
- bridge 失败时自动清除已记住的连接方式。
- WebUI 状态卡新增“重置连接方式”按钮，可回到 fetch-first 调试路径。

## 不改动

- 不改 tc / iptables / watchdog。
- 不改限速 / 延迟 / 黑白名单核心逻辑。
- 不启用 v5.2 stats RC。
- 不改变 legacy stats 默认源。

## 版本

- version: `v5.2.0-rc1.10`
- versionCode: `520020`
