# HNC v5.3.0-rc16

主题：DPI 重绑与启动自愈收尾。

## 修复

- DPI 页面新增“刷新状态”和“重新绑定 DPI”按钮。
- 新增 `bin/dpi_rebind.sh`，用于手动重启 `hnc_dpid_guard` / `hnc_dpid` 并重新写入当前热点接口配置。
- `hnc_dpid_guard.sh` 放宽接口 ready 判断：不再只依赖 `operstate=up`，只要热点接口存在且具备 IPv4、ARP 客户端、热点接口提示或常见可用状态，就允许尝试抓包。
- `service.sh` / `watchdog.sh` 加强 guard 单实例：pidfile 丢失但已有 guard 存活时修复 pidfile，不再重复拉起。
- DPI 页面 BPF Offload 提示改为明确说明“部分流量可能绕过 DPI / tc，影响识别和限速精度”。
- 新增 `bin/rc16_startup_selfcheck.sh`，用于快速检查开机/热点开关后的后端、DPI API、guard、接口状态。

## 不改动

- 不改 tc/iptables 核心限速逻辑。
- 不改 DPI 解析算法。
- 不改 stats 统计系统。

版本：`v5.3.0-rc16 / 530016`。
