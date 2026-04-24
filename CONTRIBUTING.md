# 参与贡献

HNC 欢迎:
- **bug 报告**(尤其跨 ROM 兼容性问题)
- **兼容性测试结果**(见 COMPATIBILITY.md)
- **代码 PR**

## 报 bug 前

1. 跑一次 `diag.sh` 附上输出
2. 看一遍 [已知 issue](https://github.com/lcx08091-source/hnc-v5/issues?q=is%3Aissue),避免重复
3. 标题写清楚 ROM + 设备 + 症状

## 提 PR

- 分支基于 `main`
- commit message 格式:
  ```
  <层>: <一句话>

  <为什么要改>
  <改了什么>
  <影响>
  ```
  层的选项:`tc_manager / watchdog / httpd / lsm / hotspotd / shell / docs`
- 如果改了 C/Go 代码,本地用 CI 脚本跑一下 build 再 push
- 如果改了 shell,至少 `sh -n` 过

## 代码风格

- Shell: POSIX,避免 bashism(用 `#!/system/bin/sh`)
- Go: `gofmt`,错误不吞
- C: 缩进 4 空格,每个 `if` 带 `{}`
- 注释带 **为什么** 比 **做什么** 更重要(ROM 兼容性背景、事故参考)

## 我不会接受的 PR

- 加"分析用户数据"的功能(本工具坚持本地运行)
- 去掉现有 TLS / token 验证
- 依赖一个 App 或云服务
