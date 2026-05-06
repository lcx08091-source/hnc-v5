# HNC v5.3.0-rc2 · Smart Queue 控制面

版本：v5.3.0-rc2  
versionCode：530002

本版是 v5.3 SQM 低延迟专项第二阶段，目标是把 rc1 的 SQM 基础设施接入后端 API 与本机 WebUI，仍保持默认关闭，不改变旧版限速链路。

## 新增

- 新增 `GET /api/sqm`：读取 `bin/sqm_manager.sh status`，返回当前 SQM 模式、配置档、推荐模式、qdisc 摘要与 fq_codel/CAKE 支持状态。
- 新增 `/api/action` 写操作 `sqm_set`：支持保存 `mode`、`profile`，并可触发 `sqm_manager.sh apply` 请求重建 leaf qdisc。
- WebUI 设置页新增「Smart Queue 低延迟模式」面板：
  - 关闭
  - 自动
  - 低延迟 fq_codel
  - CAKE
  - 游戏
  - 配置档：均衡 / 游戏 / 下载
- 设置页诊断刷新会同步刷新 SQM 状态。

## 安全与兼容策略

- 默认 `sqm_mode=off`，升级后不会自动改变 tc 行为。
- 不支持的 qdisc 按能力探测置灰。
- 真实 delay/jitter/loss 仍由 netem 接管，SQM 只处理 delay-free class leaf。
- Go 后端所有写入仍走 `sqm_manager.sh`，避免前后端语义分叉。

## 测试与构建

已在补丁生成环境验证：

- `sh test/run_all.sh unit/test_sqm_v53`
- `sh test/run_all.sh unit/test_sqm_v53_rc2`
- `node --check` 提取出的 `webroot/index.html` 内联脚本
- `sh bin/version_consistency_check.sh`
- `sh bin/ci_preflight.sh`：0 failures，旧 changelog/hotfix 注释 warning 仍为 1

需要在 Termux / GitHub Actions 的 Go 1.25+ 环境继续执行：

- `cd daemon/hnc_httpd && go test ./...`
- `sh daemon/hnc_httpd/build.sh`

原因：本补丁修改了 `daemon/hnc_httpd` Go 源码，打包前必须重新生成 `daemon/hnc_httpd/hnc_httpd`。
