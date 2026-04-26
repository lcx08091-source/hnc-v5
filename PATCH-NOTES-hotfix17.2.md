# HNC v5.1.0-rc1 hotfix17.2

## 目标

修复小米10 / MIUI14 上 `wlan1` 为 `qdisc mq root` 时，下行限速和延迟仍然无法应用的问题。

## 根因

现场探测结果：

- dummy 接口：HTB / netem 支持。
- 真实热点口 wlan1：mq 子队列 `parent :1` / `parent 0:1` 挂 HTB/netem/TBF 失败。
- 真实热点口 wlan1：直接 root replace 成 HTB 成功。
- 真实热点口 wlan1：root netem 成功。
- `tc qdisc replace dev wlan1 root handle 1: htb default 9999` 成功。
- HNC 原命令带 `r2q 10`，在该 MIUI tc/内核组合下失败并报 `tc: invalid argument 'root' to command`。

## 改动

- `tc_manager.sh`：HTB root / mq child / ifb root 创建命令去掉 `r2q 10`。
- `tc_manager.sh`：mq root 场景下先尝试 child HTB；失败后允许 root replace fallback。
- `tc_manager.sh`：保留 `tc_root_owned_$iface` 标记，后续 cleanup 可删除 HNC root。
- `module.prop`：升级为 `v5.1.0-rc1-hotfix17.2`。

## 预期

- 小米10：下行限速有机会恢复。
- 小米10：延迟注入有机会恢复。
- 小米10：上行仍保持不支持，因为 IFB/mirred/police 探测失败。

## 风险

此版本会在 mq root 接口上使用 root HTB fallback。若出现热点断流，清除 TC 或重启热点会恢复 ROM 默认 mq root。
