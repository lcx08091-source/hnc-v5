# HNC v5.1.0-rc1 hotfix17.7

目标：在 hotfix17.4–17.6 已经恢复小米10/MIUI14 root HTB fallback 限速与延迟的基础上，降低并发写 TC 导致的状态漂移。

## 变更

- 新增 TC 写操作全局锁：`init / restore / cleanup / set_limit / set_delay / set_all / remove` 串行执行。
- 新增 stale lock 回收，避免进程崩溃后永久占锁。
- 新增 `bin/tc_state_snapshot.sh` 只读状态快照：输出 `run/tc_state.json`、qdisc/class/filter 摘要。
- `tc_manager.sh` 每次写操作后异步刷新 TC 状态快照。
- WebUI 设备卡写操作增加 card-level busy guard，限速/延迟/清除期间禁用同卡按钮，避免重复点击排队。
- watchdog 增加 TC 自动修复熔断：连续失败 3 次后暂停 5 分钟，避免刷日志/耗电/卡顿。

## 不改变

- 不改变 root HTB fallback 的核心限速逻辑。
- 不启用上行限速；IFB/mirred/police 不支持的设备仍保持禁用。
- 不做 JSON 统一重构；该工作留到 hotfix18。
