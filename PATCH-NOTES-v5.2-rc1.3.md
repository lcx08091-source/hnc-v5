# HNC v5.2.0-rc1.3

## 目标

增加 v5.2 stats 灰度观察报告导出能力，方便真实机测试后把结果发给 Claude/Gemini/GPT 交叉审查。

## 范围

新增：
- `bin/stats_v52_gray_report.sh`
- `test/unit/test_stats_v52_gray_report.sh`
- `test/unit/test_json_health_panel_v52_rc1_3.sh`

修改：
- `bin/json_diag_bundle.sh`
- `bin/json_health_panel.sh`
- `bin/ci_preflight.sh`
- `bin/stats_v52_install_selfcheck.sh`
- `module.prop`

## 输出

实机可运行：

```sh
su -c 'sh /data/local/hnc/bin/stats_v52_gray_report.sh text'
su -c 'sh /data/local/hnc/bin/stats_v52_gray_report.sh json'
su -c 'sh /data/local/hnc/bin/stats_v52_gray_report.sh markdown'
su -c 'sh /data/local/hnc/bin/stats_v52_gray_report.sh bundle'
```

生成：
- `/data/local/hnc/run/stats_v52_gray_report.json`
- `/data/local/hnc/run/stats_v52_gray_report.txt`
- `/data/local/hnc/run/stats_v52_gray_report.md`

## 安全边界

本补丁只读诊断状态，不启用 RC，不切换 stats source，不修改 TC/iptables/watchdog/限速/延迟核心逻辑。

版本：
- `v5.2.0-rc1.3`
- `versionCode=520013`
