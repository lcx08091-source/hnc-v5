# v5.3.0-rc1

**发布日期**: 2026-05-06  
**versionCode**: 530001

---

## 一句话总结

开启 HNC v5.3 Smart Queue / SQM 低延迟专项第一阶段：先做安全基础设施，不默认改变现有限速路径。

## 新增

- 新增 `capability_probe.sh` 对 `fq_codel`、`cake`、`cake autorate-ingress` 的 dummy 安全探测。
- `run/capabilities.json` 新增：
  - `tc_fq_codel_supported`
  - `tc_cake_supported`
  - `tc_cake_autorate_ingress_supported`
  - `sqm_supported`
  - `sqm_recommended_mode`
- 新增 `bin/sqm_manager.sh`：
  - `status [iface]` 查看当前 SQM 状态 JSON
  - `get-mode` 查看当前模式
  - `set-mode off|fq_codel|cake|auto|game` 保存模式
  - `set-profile balanced|game|bulk|custom` 保存策略档
  - `apply [iface]` 通过 `tc_manager.sh restore` 安全刷新叶子 qdisc

## 行为边界

- 默认 `sqm_mode=off`，升级后不改变 v5.2.1 的日常行为。
- 开启 SQM 后，只影响**无真实延迟/抖动/丢包**的设备 class leaf。
- 设备开启 netem 延迟/抖动/丢包时，仍然强制使用 netem，避免弱网模拟失效。
- 不接管、不替换、不清空 Android/ColorOS 系统 BPF map/program。
- 不把 nftables 作为依赖。

## 技术说明

- `tc_manager.sh` 新增 SQM leaf 选择逻辑：
  - `off`：继续使用 `netem delay 0ms limit 100` 占位 leaf。
  - `fq_codel/game`：delay-free class 使用 `fq_codel` leaf。
  - `cake`：delay-free class 使用 `cake` leaf，失败自动回退 netem 占位。
  - `auto`：根据 capabilities 选择推荐模式。
- `set_delay 0 0 0` 会在 SQM 开启时回到 SQM leaf；设置真实 delay/jitter/loss 时会切回 netem。

## 测试

新增回归测试：

- `test/unit/test_sqm_v53.sh`

覆盖：

- capability probe 输出 SQM 相关字段。
- `sqm_manager.sh` 默认 off。
- `sqm_manager.sh set-mode fq_codel` 可持久化。
- 非法模式会失败。

---

# v5.2.1

**发布日期**: 2026-05-02  
**versionCode**: 520100 (从 rc1.22 的 520032 提升)  
**daemon md5**: `0d869b3de76d6a97b53253edb4d8c2d6`

---

## 一句话总结

整合 v5.2.0-rc1.22 + 在真机环境下追出来的 9 个独立缺陷修复（合称 webfix1–9），是 v5.2 系列里**首个面向日常使用**的稳定版。核心功能（限速 / 延迟 / 黑白名单 / 远程访问）零改动。

---

## 用户视角的变化（简版）

| 你之前可能遇到的问题 | v5.2.1 已修复 |
|---|---|
| 升级到 rc1.22 后 WebUI 按钮全部失灵，热点状态卡片显示但点不动 | ✅ 修复 patch 损坏的 JS 语法 |
| 打开 WebUI 卡 1 分钟左右才出现内容（特别是 SukiSU manager） | ✅ 首屏从 ~48 秒降到 < 1 秒 |
| WebUI 频繁弹 toast：`HTTP fetch failed; KSU bridge auto disabled` | ✅ daemon 加 CORS 头，HTTP 直连工作 |
| 应用限速 / 注入延迟时 UI 卡顿 200-500ms | ✅ 走 HTTP 直连后无主线程阻塞 |
| 提示"当前设备内核不支持 IFB/mirred，上行限速已禁用"（明明以前能用） | ✅ 修复 capability 探测逻辑，上行限速可用 |
| 注入延迟时弹 `netem apply failed` 错误 | ✅ 修复 daemon 解析 stderr 污染问题 |
| 配对码生成失败弹窗的"关闭"按钮点不动 | ✅ 按钮可点 |
| 统计页"限速中/延迟注入"数字偏大（包含离线历史设备） | ✅ 只算在线设备 |
| 主页设备过滤卡片首屏一闪无主题样式（一根灰条） | ✅ 与其他卡片样式统一 |
| watchdog 日志疯狂刷"mirred missing repairing" | ✅ 修复 grep 模式，日志清净 |

---

## 修复细节（技术版，按发现顺序）

### 1. patch tarball JS 语法损坏 (webfix1)

`webroot/index.html` 第 4468/4478 行被上游 patch 工具错误展开，把 `$("#stats-v52-source-status")` 变成 `0 0"#stats-v52-source-status")` —— `$(` 在 patch 生成管道里被某个 shell 当成命令替换执行了，把 `$("#...")` 干掉了。

整个 `<script>` 块因此 `SyntaxError`，所有 `onclick` 不绑定，UI 看似正常但全部按钮死。

**修法**：恢复成 `$("#...")`。

### 2. 首屏 48 秒同步 shell 阻塞 (webfix2)

rc1.22 在 `init()` 同步段加了 `initStatsSourceSelect()`，里面通过 `kexec("sh stats_v52_source_switch.sh text")` 调一个会级联 6 个子脚本的 shell。SukiSU manager 的 `window.ksu.exec` 是同步 fork+exec+wait，主线程被锁 ~48 秒（实测 `FCP=48860ms`）。

**修法**：
- Shell 端加 `HNC_FIRSTLOAD_FAST=1` 让只读模式跳过 `run_observe` 级联（约 120× 加速）；
- JS 端把 `refreshStatsV52SourceStatus` 用 `setTimeout(4000)` 推到首屏之后。

### 3. loopback HTTP 未开 CORS (webfix3)

daemon `hnc_httpd` 只在 HTTPS 远程端口（8443）设 CORS，loopback 端口（8444）裸返。SukiSU manager 把 WebUI 装载到 `https://mui.kernelsu.org`，从那里 fetch `http://127.0.0.1:8444/api/*` 是跨 origin 请求，被浏览器拦下，WebUI 退回到 `window.ksu.exec` 桥接（每次 50–200ms 同步阻塞）。

**修法**：新增 `loopbackCORSMiddleware`，严格白名单单一 origin `https://mui.kernelsu.org`，OPTIONS preflight 返回 204。HTTPS 远程服务**不动**（保留原有鉴权层）。

### 4. CORS 与 daemon 反 CSRF 冲突 + IFNAMSIZ 网卡名溢出 (webfix4)

两个独立问题，因相互掩盖一并修复：

- **(a)** daemon 的 loopback 免鉴权路径要求 `Origin` 和 `Referer` 都为空（rc3 时代写下的反 CSRF 措施）。webfix3 加了 CORS 头之后，SukiSU 的 WebView 总是带 `Origin: https://mui.kernelsu.org`，daemon 看到非空 Origin 直接走 cookie auth，没 cookie → 401。Middleware 在白名单 origin 校验通过后剥掉 Origin/Referer，让免鉴权路径触发。

- **(b)** `bin/capability_probe.sh` 用 `hnc_probe_dummy_$$` / `hnc_probe_peer_$$` / `hnc_probe_ifb_$$` 做临时网卡名。PID 4-5 位时这些名字 19-21 字符，超过 Linux `IFNAMSIZ=15`（含 NUL 是 16）。`ip link add` 永远拒绝，dummy 创建失败，下游 HTB / netem / mirred / IFB 探测全部 skip 真测分支，capabilities.json 全是 null/false。改为 `hnc_p_d_NNNNN`（13 字符，PID 取后 5 位）。

### 5. capability_probe qdisc + parent 不兼容 (webfix5)

`ensure_ingress_parent()` 优先尝试 `clsact` qdisc，但下面所有 filter 测试用 `parent ffff:`（这是 ingress qdisc 的固定 handle 简写）。

老版本 Android iproute2（ColorOS RMX5010 装的是 `ss171113`，2017 年的）不接受 `clsact + parent ffff:` 组合，返回：
- `RTNETLINK answers: Invalid argument` （u32 / mirred / police）
- `Unknown action "noact"` （matchall / flower）

这些错误信号被 capability_probe 当作"内核不支持"，UI 显示"IFB/mirred 不支持，上行限速已禁用"。但 tc_manager 实际操作时用 ingress qdisc，所以**上行限速一直是工作的**——只是 capability 报告错了，前端禁用了输入框。

**修法**：`ensure_ingress_parent()` 优先用 `ingress` qdisc，clsact 作为 fallback。ingress + parent ffff: 是从 ~2010 年 iproute2 起就完全兼容的组合。

### 6. watchdog mirred 检测 grep 不匹配 + marker 永久卡死 (webfix6)

两个紧密相关的问题：

- **(a)** `bin/watchdog.sh` 检测 ingress mirred filter 用 `grep -q "mirred.*redirect dev ifb0"`。但 tc 实际输出是 `mirred (Egress Redirect to device ifb0)` —— 大写 `Redirect`、`to device` 不是 `dev`。pattern **永不匹配**，watchdog 每分钟报一次"missing"并触发"修复"（修复成功因为 mirred 早就在了），日志被永久 spam。改为大小写不敏感的 `grep -qi "mirred.*ifb0"`。

- **(b)** `tc_manager.sh` / `watchdog.sh` 在首次失败时写 sticky marker 文件（如 `uplink_unsupported`、`tc_qos_fallback`），但只有 `hotspot_autostart.sh` 在自启时清。多数用户不开自启 → marker **永远不被清** → 即使后续 capability 探测改对了，runtime 检查仍走"不支持"分支。capability_probe 跑完确认能力支持时，主动清相关 marker，让自愈链路畅通。

### 7. json_set.sh stderr 泄漏到 daemon (webfix7)

`bin/json_set.sh` 在 `hnc_json` 二进制不可用时 `echo "[WARN] ..." >&2` 提示走 fallback。但 `daemon/hnc_httpd/action.go` 用 `cmd.CombinedOutput()` —— **stdout 和 stderr 合并**。WARN 字符串于是混进了 daemon 解析的"返回值"前面：

```
json_set: [WARN] hnc_json device_get unavailable; count=53385
85
```

第二行才是真实 mid (`85`)，但 daemon 的 `intRE.MatchString` 看第一行就 fail，错误信息 surface 成 "mid invalid: device_get returned non-integer mid"，前端 toast 显示 "netem apply failed"。

`count=53385` 同时揭示了第 8 个问题：hnc_json 在测试设备上**失败了 5 万 3 千次**，没人看那个计数器。

**修法**：WARN 用 `printf >> $JSON_LEGACY_FALLBACK_LOG` 改写到日志文件，**不输出到 stderr**。

### 8. hnc_json 缺少可执行权限 (webfix8)

`post-fs-data.sh` 显式 `chmod 755` 一组无 `.sh` 后缀的二进制：

```sh
for _b in hotspotd hnc_ipc hnc_tc_ingress mdns_resolve; do
```

**漏了 `hnc_json`**。该文件是个 awk 脚本但没 .sh 后缀，KSU 模块解压后保持 644，`json_set.sh` 每次调它都 `Permission denied`，回退到内置 awk 实现。这就是 webfix7 看到的"5 万次 fallback"的根因。

**修法**：`hnc_json` 加入 chmod 列表。

### 9. 用户反馈的 4 个 UX bug (webfix9)

- **`pair_gen.sh` find -delete 污染 stdout**：脚本最后 `find ... -delete 2>/dev/null` 用来清理 60 分钟前的 `pair_success.*` 残留。Linux GNU find `-delete` 静默，但 Android 的 toybox find **会把每个被删的路径 print 到 stdout**。残留文件存在时，daemon 收到的"JSON 输出"实际是：
  ```
  /data/local/hnc/run/pair_success.OF4qRclPv2Hi
  {"ok":true,"pin":"...","session_id":"..."}
  ```
  前端 `JSON.parse` 在第一行炸，弹"配对码生成失败"。修法：`>/dev/null 2>&1` 双重重定向。

- **配对失败弹窗的"关闭"按钮点不动**：按钮用了 `data-action="modal-close"` 属性，但**代码里没有任何 dispatcher 监听这个 action**。其他模态框都是 `onclick="hideModal()"` 或 `data-action="cancel"`。可能是早期某版有 modal-close dispatcher 后来重构掉了，这处遗忘清理。结果是用户被永久关在弹窗里直到 force-stop SukiSU。修法：直接改用 `onclick="hideModal()"`。

- **统计页计数包含离线历史设备**：`updateCounters()` 计算 `limited` 和 `delayed` 时没过滤 `status === 'online'`。一台设备的规则保存在 rules.json 里，即使设备已离线很久也会被算入。9 台历史设备 1 台在线时显示"2 限速中, 6 延迟注入"——令人困惑。修法：加 `d.status === 'online' &&` 前置过滤。

- **设备过滤卡片首屏样式不一致**：用了自定义 `.device-filter-bar` 而非项目通用的 `.glass`。CSS 变量在两类元素上的解析时机有微差，首屏一闪显示无主题状态（看起来像一根灰横条）。修法：加上 `.glass` 类，让它走和其他卡片同一套渲染路径。

---

## 包结构清理

v5.2.1 同时整理了发布 zip 的内容：

| 类别 | rc1.22 | v5.2.1 | 说明 |
|---|---|---|---|
| 文件总数 | 338 | 220 | -118 |
| zip 大小 | 5.1 MB | ~5.0 MB | 变化不大（多数被删的是文档）|
| `PATCH-NOTES-*.md` | 82 个 | 0 | 历史发布说明，已归档到仓库 docs-archive/ |
| 顶层 `.md` 文件 | 11 个 | 4 个 | 仅保留用户需要的：README, CHANGELOG, COMPATIBILITY, SECURITY |
| `CHANGELOG.md` | 326 KB（85 个版本节）| ~12 KB | 仅保留 v5.2.1 节，历史归档 |
| `third_party_build/` | 含 | 不含 | 开发用，运行时不需要 |
| `STAGE-*.md`、`README-BATCH2.md` | 含 | 不含 | 开发过程文档 |
| `INTEGRATION.md` (v5.0 alpha)、`HACKING.md`（60 KB）、`ROADMAP.md`、`INSTRUCTIONS.md`（v5.1 时代）、`CONTRIBUTING.md` | 含 | 不含 | 开发文档/过时文档，归档到仓库 |
| `test/` | 含 | **保留** | `post-fs-data.sh` 会复制到 `/data/local/hnc/test/` 让用户能跑测试，不能删 |

---

## 安全边界

未触动以下任何一项：
- tc / iptables 规则计算逻辑
- watchdog 状态机
- 限速精度策略 (htb / netem / mq fallback)
- 黑白名单匹配规则
- 远程访问鉴权 (cookie / token)
- KSU IPC 协议
- `service.sh` / `post-fs-data.sh` 启动时序

9 项均为缺陷修复，不引入新功能、不改变 API、不移除任何选项。

---

## daemon binary

```
v5.2.1 daemon md5: 0d869b3de76d6a97b53253edb4d8c2d6
- Go 源码 vs rc1.22: server.go +37 / main.go +5 (CORS middleware)
- Go 源码 vs webfix9:  完全相同 (webfix5-9 仅改 shell + HTML)
- v5.2.1 重新构建嵌入新版本字符串 (-X main.version=v5.2.1)
```

## 安装

新安装：直接刷 `HNC-v5_2_1-arm64.zip`。

从 rc1.22 升级：
1. SukiSU manager → 模块 → HNC → 卸载（建议保留数据）
2. 重启
3. 刷 `HNC-v5_2_1-arm64.zip`
4. 重启

如果之前应用过 webfix1-9 的就地热修复脚本，刷 zip 时模块会被完整覆盖，自动接管。

## 已知限制

- mq child htb（最精确队列链路）在 Snapdragon 8 + ColorOS / MIUI 平台上仍**无法启用**——内核拒绝在 mq 的子 class 上挂 htb，HNC 自动 fallback 到 root htb（"稳准"模式）。这是平台限制不是 HNC bug。fallback 模式精度对手机热点场景完全够用，UI banner "无法使用最精确队列链路" 是诚实告知，不是错误。

- `hnc_json` 二进制本身在某些设备上仍可能失败（测试机上 webfix8 chmod 之后失败次数从 5 万降到 0，但其他设备的具体失败原因没有跟进调查）。失败时 awk fallback 接管，功能上无影响。

---

## 历史版本

完整历史变更记录（v5.0 alpha → v5.2.0-rc1.22, 共 85 个版本节点）已归档到
`docs-archive/CHANGELOG-full-history.md`，仅作为开发参考保留，**不打入模块 zip**。

如需查阅过往版本说明，请访问项目 repository。
