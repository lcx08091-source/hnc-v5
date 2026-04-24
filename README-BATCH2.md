# HNC v5.1.0-rc2 Patch Package (第 2 批 · 开源就绪)

## 代码修复

| ID | 文件 | 修复 |
|---|---|---|
| **S1** | `bin/tc_manager.sh` | `restore_rules` 加 loss_pct 解析, 重启后丢包率不再被清零 |
| **H1** | `bin/diag.sh` | 修错误的 iptables 链名 (HNC_LIMIT_DOWN/UP → HNC_RESTORE/SAVE) |
| **H2** | `bin/diag.sh` | version 不再硬编码 v3.8.6, 从 module.prop 动态读 |
| **X-G2** | `daemon/hnc_httpd/main.go` + `build.sh` | version 用 ldflags 注入, 不再硬编码 v4.1.0 |

## 开源发布就绪

| 文件 | 用途 |
|---|---|
| `README.md` | 用户导向重写 |
| `COMPATIBILITY.md` | ROM 兼容性矩阵 |
| `CONTRIBUTING.md` | 贡献流程 |
| `SECURITY.md` | 漏洞报告渠道 (lcx08091@gmail.com) |
| `uninstall.sh` | Magisk 卸载钩子 (自动 cleanup + 备份) |
| `.github/ISSUE_TEMPLATE/*` | GitHub issue 模板 |

## 使用方法

```sh
cd ~/hnc-v5
unzip -o /sdcard/Download/hnc-rc2-patch-batch2.zip
git status
git add -A
git commit -m "v5.1 RC2 batch 2: audit fixes + open-source docs

Code fixes:
- S1: tc_manager restore_rules parses loss_pct
- H1: diag.sh checks correct iptables chains
- H2: diag.sh version read from module.prop
- X-G2: hnc_httpd version via ldflags

Open-source docs:
- README.md rewritten (user-facing)
- COMPATIBILITY.md + CONTRIBUTING.md + SECURITY.md
- uninstall.sh + GitHub issue templates"

git push
```

CI 编完后去 GitHub Releases 发 v5.1.0-rc2 (含所有 rc2 patch 的 artifact).
