# HNC v5.0.0-beta.4 hotfix2: set_fail SEGV 真因修复

## 问题
hotfix1 后 hotspotd 仍 SIGSEGV crash loop, tombstone 显示崩在
`/data/local/hnc/bin/hotspotd pc 0x168c4`,日志只到 `[lsm] step4: parse_bpf_object`
后停止,没有 step4 完成或 FAIL 输出。

## 根因(基于 addr2line 反查证据)
`addr2line -e hotspotd 0x168c4` 解析为 **`set_fail` 函数 line 127**
(`g.stat.state = HNC_LSM_FAILED` 那行,`pthread_mutex_lock` 之后)。
fault addr `0x...5e8` 在 `[anon:thread signal stack]`,正是 ARM64
va_list register save area 区域。

调用链:
1. `parse_bpf_object` 在某 syscall 失败(可能 mmap/open errno=ENOENT)
2. 返回 -errno → init 调 `set_fail("parse_bpf_object: %s", strerror(...))`
3. `set_fail` 内 `pthread_mutex_lock(&g.stat_lock)` + `va_start(ap, fmt)` 段错

之前以为崩在 `parse_bpf_object` 内,实际是它 graceful 返回后 set_fail 段错,
真正的失败原因被吞了。

## 修复
两处:

1. **`g.stat_lock` 改用 `PTHREAD_MUTEX_INITIALIZER` 静态初始化**
   - 删除 hnc_lsm_init 里的 `pthread_mutex_init(&g.stat_lock, NULL)`
   - 排除任何 dynamic init 顺序问题

2. **`set_fail` 重写 — fprintf 优先**
   ```c
   static void set_fail(const char *fmt, ...) {
       char tmp[128];
       va_list ap;
       va_start(ap, fmt);
       vsnprintf(tmp, sizeof(tmp), fmt, ap);
       va_end(ap);
       /* 关键:先打日志,即便 mutex 段错也能看到原因 */
       fprintf(stderr, "[lsm] FAIL: %s\n", tmp);
       fflush(stderr);
       /* 然后再写共享状态 */
       pthread_mutex_lock(&g.stat_lock);
       g.stat.state = HNC_LSM_FAILED;
       snprintf(g.stat.fail_reason, sizeof(g.stat.fail_reason), "%s", tmp);
       pthread_mutex_unlock(&g.stat_lock);
   }
   ```

## 装机
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_0_0-beta4-hotfix2.zip .
unzip -o HNC-v5_0_0-beta4-hotfix2.zip
rm HNC-v5_0_0-beta4-hotfix2.zip

git diff --stat
git add -A
git commit -m "v5.0.0-beta.4 hotfix2: set_fail SEGV root cause fix

addr2line traced PC 0x168c4 to set_fail line 127 (mutex_lock + va_start).
Two fixes:
1. g.stat_lock uses PTHREAD_MUTEX_INITIALIZER (static init), no dynamic
   init race during early failure paths.
2. set_fail formats and prints FAIL message to stderr BEFORE acquiring
   lock or writing shared state. Even if mutex/va_args path SEGVs,
   underlying failure reason now reaches log.

This unblocks LSM diagnosis: any future LSM init failure will print
[lsm] FAIL: <real reason> before any potential SEGV."
git push

# 等 CI → 装 → 重启 → 立刻看日志
su -c "grep -iE 'lsm|sched|tier' /data/local/hnc/logs/hotspotd.log | tail -50"
```

## 期望日志(成功路径)
```
[lsm] BPF LSM active in kernel
[lsm] target limit_map id=N
[lsm] step3: create_ctrl_map
[lsm] step3: ctrl_map fd=N
[lsm] step3: ringbuf_map fd=N
[lsm] step4: parse_bpf_object
[lsm] step4: parsed bpf.o: NN insns, NN relocs, btf=NNNN bytes
[lsm] step5: using attach_btf_id=0
[lsm] step6: BPF_BTF_LOAD
[lsm] step6: prog_btf_fd=N
[lsm] step7: BPF_PROG_LOAD
[lsm] step7: LSM prog loaded, fd=N
[lsm] step8: populate ctrl map
[lsm] step9: mmap ringbuf
[lsm] step9: mmap OK (cons=0x... prod=0x... data=0x...)
[lsm] step10: attach LSM
[lsm] step10: link_fd=N
[lsm] step11: start ringbuf consumer thread
[lsm] ACTIVE. protecting map_id=N ifindex=22 hotspotd_pid=N
```

## 期望日志(失败路径,但不再 crash loop)
```
[lsm] step4: parse_bpf_object
[lsm] FAIL: parse_bpf_object: <精确 errno>     ← 这条以前看不到
[sched] BPF LSM guard FAILED, fallback to passive disable
[sched] worker started ...
... hotspotd 正常运行 ...
```

如果还失败,日志里现在能看到具体 reason,告诉我下一步。
