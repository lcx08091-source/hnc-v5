# HNC v5.3.0-rc5 · 发布链路 / 灰度收口

目标：不继续堆 SQM 新功能，先把 v5.3 的安装包识别、实机最低限度自检、测试残留清理流程收稳。

## 新增

- `bin/artifact_pick_flashable.sh`
  - 自动识别 GitHub Actions 外层 wrapper ZIP。
  - 如果传入的是外层 ZIP，自动提取里面真正可刷的模块 ZIP。
  - 对最终 flashable ZIP 调用 `artifact_sanity_check.sh`。
  - 成功时输出 `flashable_artifact=<path>`，方便脚本/Actions 继续使用。

- `bin/rc_selfcheck_v53.sh`
  - 实机只读自检脚本。
  - 检查 `module.prop`、`hnc_httpd -version`、`/api/sqm`、当前热点接口、fq_codel/CAKE 能力、qdisc 状态。
  - 自动提示是否存在 `netem` 测试残留。
  - 报告写入 `/data/local/hnc/run/rc_selfcheck_v53.latest`。

- `bin/hnc_cleanup_test_rules_v53.sh`
  - 谨慎清理测试用 `netem` leaf qdisc。
  - 默认只读 dry-run。
  - 只允许清理 `parent 1:<classid>` 下的 `netem` leaf。
  - 不删除 root qdisc、不删除 clsact、不改 iptables、不改 JSON。

- `test/unit/test_artifact_release_rc5.sh`
  - 回归测试 direct flashable ZIP 和 Actions outer wrapper ZIP 的自动识别/提取。

## 改动

- `ci_preflight.sh --artifact <zip>` 接入 `artifact_pick_flashable.sh`。
  - 传入外层 Actions ZIP 时，会先提取内层模块 ZIP，再对内层 ZIP 做严格检查。
  - 继续保留 `artifact_sanity_check.sh` 的直接刷入检查能力。
- 版本升级到 `v5.3.0-rc5 / versionCode=530005`。
- 更新 WebUI changelog。

## 使用

下载 Actions 产物后：

```sh
sh bin/artifact_pick_flashable.sh /sdcard/Download/HNC-v5_3_0-rc5-arm64.zip /sdcard/Download/hnc-rc5-picked
```

脚本会输出：

```text
flashable_artifact=/sdcard/Download/hnc-rc5-picked/HNC-v5_3_0-rc5-arm64.zip
```

装机后最低限度实机检查：

```sh
su -c 'sh /data/local/hnc/bin/rc_selfcheck_v53.sh'
```

查看/清理测试 `netem` 残留：

```sh
su -c 'sh /data/local/hnc/bin/hnc_cleanup_test_rules_v53.sh status --iface=wlan2'
su -c 'sh /data/local/hnc/bin/hnc_cleanup_test_rules_v53.sh clear-parent --iface=wlan2 --parent=1:85 --yes'
```

## 风险

- 不改 tc/iptables/netem 主链路。
- 不改 BPF/offload 逻辑。
- 不改 SQM 真实应用策略。
- 清理脚本默认 dry-run，且只清用户明确指定或确认的 HNC-like netem leaf。
