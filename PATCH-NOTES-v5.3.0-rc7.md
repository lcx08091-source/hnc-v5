# HNC v5.3.0-rc7

## 目标

修复 rc5 中 SQM 按钮点击后容易卡死/超时的问题，但不采用 rc6 的“只保存不应用”止血方案，而是把 SQM apply 改成真正轻量的增量操作。

## 主要变化

- `sqm_manager.sh apply` 不再调用 `tc_manager.sh restore`。
- SQM apply 只增量替换默认 HTB leaf：`parent 1:9999 handle 9999:`。
- CAKE 不支持时不会尝试 CAKE，自动回退 `fq_codel`。
- 如果默认 leaf 上存在真实 active netem，则保守跳过，避免覆盖弱网规则。
- WebUI 增加 `sqmBusy` 防连点，避免连续点击堆请求。
- WebUI 针对 CAKE 不支持给出明确提示。
- 文案改为“增量替换默认 leaf qdisc”，不再误导为全量重建。

## 设计原则

- 不动 HTB root。
- 不动设备 class。
- 不动设备 filter。
- 不动 iptables mark。
- 不动 IFB / mirred / police。
- 不动 BPF/offload。
- 不全量 restore。

## 版本

- version: `v5.3.0-rc7`
- versionCode: `530007`
