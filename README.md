# HNC v5.1 Plan B — kprobe + counter-write

## 根因
ColorOS kernel 6.6.102 禁用 `CONFIG_FUNCTION_TRACER`(反 root 加固),
BPF LSM / fentry / fexit 均依赖 trampoline → 全部 `-ENOTSUPP`。

kprobe 走另一套机制(`CONFIG_KPROBES=y`,ColorOS 保留),**可以 attach**。

## 策略
- `SEC("kprobe/security_bpf")`:kprobe hook 到 kernel `security_bpf()` 入口
- BPF 程序:检测 `cmd=BPF_MAP_UPDATE_ELEM + target_map + U64_MAX + 非 hotspotd` 
  → 发 ringbuf 事件
- Userspace:ringbuf consumer 收到事件 → **立刻** `bpf_map_update_elem(limit_map, ifindex, 0)` 盖掉

**相对 LSM active 差一个 kernel→userspace→kernel 的往返(~100μs 级)。
实际 framework 的 U64_MAX 短暂存在几十到几百微秒,fast path 来不及激活。**

## 修改文件
1. `daemon/hotspotd/lsm/hnc_limit_map_guard.bpf.c` (141 行)
   - SEC 改 `kprobe/security_bpf`
   - 函数签名改 `BPF_KPROBE(hnc_check_bpf, cmd, attr, size)` (3 参数,无 prev_ret)
   - 去掉 `return -EPERM` 逻辑,kprobe retval 无效

2. `daemon/hotspotd/lsm/hnc_lsm_loader.c` (411 行)
   - `bpf_program__attach_lsm` → `bpf_program__attach_kprobe(prog, false, "security_bpf")`
   - `ringbuf_handle_event` 加 counter-write:收到事件立刻 `bpf_map_update_elem(limit_map, ifindex, 0)`
   - 日志新增 `[lsm] COUNTER-WRITE: ... latency=NNNus` 看实际延迟

## 装机
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-planB.zip .
unzip -o HNC-v5_1-planB.zip
rm HNC-v5_1-planB.zip

# 重编 BPF .o (用 local clang 或让 CI 重编)
# 在 Termux:
pkg install clang -y 2>/dev/null   # 如果没装
cd daemon/hotspotd/lsm
clang -O2 -g -target bpf -D__TARGET_ARCH_arm64 \
      -I../../../third_party_prebuilt/libelf/include \
      -I. \
      -c hnc_limit_map_guard.bpf.c \
      -o ../../../bpf/hnc_limit_map_guard.bpf.o
llvm-strip -g ../../../bpf/hnc_limit_map_guard.bpf.o 2>/dev/null || true
cd ~/hnc-v5

# 或者只 push, 让 CI 重编
git add -A
git commit -m "v5.1 Plan B: kprobe + counter-write (ColorOS LSM workaround)

ColorOS disables CONFIG_FUNCTION_TRACER, blocking BPF LSM / fentry
trampoline (-ENOTSUPP). Switch to kprobe/security_bpf (CONFIG_KPROBES=y
preserved). Since kprobe cannot deny, use counter-write: BPF detects
suspicious write, emits ringbuf event, userspace rewrites limit_map to
0 within microseconds. Fast path fails to sustain; framework's U64_MAX
is overwritten before tethering BPF sees stable state."
git push
```

## 期望日志
```
[lsm] step1: BPF LSM active in kernel
[lsm] step2: target limit_map id=3
[lsm] step3: open OK
[lsm] step4: load OK
[lsm] step5: prog + maps resolved
[lsm] step6: ctrl populated
[lsm] step7: bpf_program__attach_kprobe(security_bpf)
[lsm] step7: kprobe attached to security_bpf       ← 关键, 这次应该成
[lsm] step8: ringbuf consumer started
[lsm] ACTIVE. protecting map_id=3 ifindex=22 hotspotd_pid=NNNN
```

当 framework 写 limit_map 时:
```
[lsm] COUNTER-WRITE: comm=system_server pid=NNNN ifindex=22 val=0xffffffffffffffff rewrite=OK latency=150us
```

## 故障模式
- **如果 kprobe attach 也失败** (极少数):报 "cannot find kernel btf id" 或
  "No such file or directory" → kprobe event_id 没建好,需要 `echo 1 >
  /sys/kernel/tracing/tracing_on` 或类似
- **如果 attach 成功但没收到事件**:可能 BPF_CORE_READ 字段偏移错
  (libbpf 做 CO-RE 重定位,应该对,但 ColorOS kernel 可能魔改 struct)
- **如果 counter-write 报 EPERM**:limit_map 白名单限制 hotspotd,
  需要 v5.2 确认
