---
name: Compatibility Report
about: 报告你 ROM/设备 的兼容性测试结果
title: "[Compatibility] <ROM name> <device model>"
labels: compatibility
---

## 测试结果

<!-- 在下面打勾 -->

- [ ] 模块能装上,不崩
- [ ] WebUI 能打开(http://127.0.0.1:8444)
- [ ] 能看到连接热点的设备列表
- [ ] 能限速某台设备的下行
- [ ] 能限速某台设备的上行
- [ ] 能注入延迟
- [ ] 重启后规则能恢复

## 诊断包

```sh
su -c 'sh /data/local/hnc/bin/diag.sh' > /sdcard/hnc_diag.txt
```

<details>
<summary>diag.sh 输出</summary>

```
(粘贴这里)
```
</details>

## 环境

- **ROM**:
- **设备**:
- **Android 版本**:
- **内核版本**:
- **Root 方案**:

## 热点 iface 名

```
ip link show | grep -E "wlan|ap|softap"
```

## 特殊现象

<!-- 比如 "装上后开机卡 5 秒"、"打开 WebUI 必须等 30 秒"、"限速生效但精度只有 ±30%" -->
