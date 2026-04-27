# HNC v5.1.0-rc1 hotfix18.7

## 目标

把 hotfix18.6 的独立 JSON 健康页面正式接入主 WebUI，但不直接覆盖用户当前最新 `webroot/index.html`。

## 改动

- 新增 `bin/webui_embed_json_health_entry.sh`
  - 在当前仓库的 `webroot/index.html` 中注入一个幂等的 JSON 健康入口。
  - 优先尝试把入口挂到“诊断 / 设置 / 调试 / 系统”相关区域。
  - 找不到合适区域时，降级为右下角玻璃风格悬浮入口。
  - 入口会读取 `json_health_panel.sh` 的状态，显示 `JSON 正常 / 警告 / 异常`。
  - 点击可打开 `json-health.html` 独立诊断页。

## 设计取舍

- 不直接把整个 `index.html` 放进 patch，避免覆盖你当前频繁迭代后的最新 UI。
- 采用“在当前 index.html 上注入小块 CSS/JS”的方式，保持主界面现有设计和逻辑。
- 脚本幂等，已经注入过不会重复插入。

## 使用

在复制 changed-files 后执行：

```sh
sh bin/webui_embed_json_health_entry.sh .
```

然后再 `git diff --stat`、提交、push。

## 风险

低。仅新增主 WebUI 的入口和状态读取，不修改 live JSON，不改变限速/iptables/tc 逻辑。
