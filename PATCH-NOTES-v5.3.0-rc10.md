# HNC v5.3.0-rc10

目标：修复 SQM 在热点未开启 / iface.cache 过期时误报 `sqm apply failed` 的问题。

## 变化

- `sqm_manager.sh apply` 在热点接口不存在时不再返回失败；只记录跳过并返回状态 JSON。
- `/api/sqm`/本地 status 输出升级为 schema 3，新增：
  - `available`
  - `iface_present`
  - `hotspot_active`
  - `can_apply`
- WebUI 在热点未开启时显示“待生效”，并提示“设置已保存，开启热点后再应用”。
- 新增 `test/unit/test_sqm_v53_rc10.sh` 覆盖 stale iface / 热点关闭场景。

## 不做

- 不引入异步 job 队列。
- 不改 HTB/root/netem/iptables/BPF 主链路。
- 不改变 rc7 的增量 leaf apply 设计。
