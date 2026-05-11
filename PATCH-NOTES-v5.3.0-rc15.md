# HNC v5.3.0-rc15

目标：修复 GitHub Actions 重新编译后 `hnc_httpd` 丢失 DPI API 路由的问题。

## 修复内容

- 固化 Go 源码级 DPI API：
  - `daemon/hnc_httpd/api_dpi_v53.go`
  - `/api/dpi_state`
  - `/api/dpi_probe`
  - `apiDPIState`
  - `apiDPIProbe`
- `server.go` 明确注册 DPI API 路由。
- `middleware.go` 将 DPI API 纳入敏感只读接口列表。
- `build.sh` 在 `go build` 后强制检查二进制字符串：
  - `/api/dpi_state`
  - `/api/dpi_probe`
  - `apiDPIState`
  - `apiDPIProbe`
- `artifact_sanity_check.sh` 继续检查最终 zip 内的 `hnc_httpd` 是否含 DPI API。
- 版本升至 `v5.3.0-rc15 / 530015`。

## 验证重点

刷入后确认：

```sh
curl -s http://127.0.0.1:8444/api/dpi_state
curl -s http://127.0.0.1:8444/api/dpi_probe
```

两项都不应返回 `404 page not found`。
