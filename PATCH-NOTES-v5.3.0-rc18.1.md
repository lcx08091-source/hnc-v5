# HNC v5.3.0-rc18.1

类型：release gate / 打包完整性收尾

## 目标

rc18 已经把 DPI L1 观察链路接入模块包，但打包门禁还没有强制检查 `bin/hnc_dpid`，并且后端二进制版本字符串容易出现滞留。本版本只做收尾，不引入 L2/L3 新功能。

## 变更

- 升级 `module.prop`：`v5.3.0-rc18.1 / 530019`。
- `bin/artifact_sanity_check.sh` 增加 `bin/hnc_dpid` 强校验：
  - 必须存在于 ZIP 根路径；
  - 必须能提取；
  - 必须是 ARM/AArch64 ELF；
  - 必须包含 `0.1.0-rc1.2-fixed` 或后续 rc1.x 版本字符串。
- `bin/ci_preflight.sh` 增加源码树和 artifact 级 `bin/hnc_dpid` 检查：
  - 存在、可执行、非空；
  - ELF machine 检查；
  - 版本字符串检查；
  - artifact 必须包含 `bin/hnc_dpid`。

## 非目标

本版本不改动：

- tc / iptables / watchdog 核心规则；
- DPI L2 per-client 归因；
- DPI L3 分类规则库；
- DNS cache / flow table / 分类限速。

## 构建要求

构建 `HNC-v5_3_0-rc18_1-arm64.zip` 时必须重新编译 `daemon/hnc_httpd/hnc_httpd`，确保内嵌版本不再停留在 `v5.3.0-rc17`。
