# HNC v5.0.0-beta.4 hotfix1: BTF parser SEGV fix

## 问题
beta.4 装机后 hotspotd 静默崩溃,tombstone 显示
`SIGSEGV SEGV_MAPERR fault addr 0x787...5e8`,崩在 `[lsm] target limit_map id=3` 之后。

## 根因
`find_btf_id_by_name()` 自己解析 vmlinux BTF (3.3 MB) 找 `security_bpf` hook id,
但手撸的 BTF parser 对 type kind padding 计算错误,导致 `name_off` 越界,
`strcmp(strtab + name_off, target)` 读到未映射地址,SEGV。

## 修复
完全删除 `find_btf_id_by_name`,改用 Linux 5.11+ 的标准做法:
- BPF_PROG_LOAD 时传 `attach_btf_id=0`
- kernel 读 prog 自己 BTF 里 clang 生成的 `BTF_KIND_DECL_TAG("lsm/bpf")`
- kernel 自动解析为 vmlinux 里 `security_bpf` 的 BTF id

不需要 user-space BTF 解析,代码 -90 行,SEGV 风险消除。

同时给 init 每个 step 加了 `fprintf(stderr) + fflush()`,失败时能精确
定位到崩在哪个 step。

## 装机
```sh
# Termux
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_0_0-beta4-hotfix1.zip .
unzip -o HNC-v5_0_0-beta4-hotfix1.zip
rm HNC-v5_0_0-beta4-hotfix1.zip

git add -A
git commit -m "v5.0.0-beta.4 hotfix1: BTF parser SEGV fix

Removed in-process BTF parser (find_btf_id_by_name) which had
incorrect type kind padding calculation causing name_off overflow
into unmapped memory (SEGV_MAPERR observed on RMX5010 ColorOS 16).

Replaced with kernel auto-infer: attach_btf_id=0 + correct
prog_btf_fd, kernel resolves lsm/bpf hook from prog's BTF DECL_TAG.

Added step-by-step fprintf+fflush to LSM init for precise crash
location reporting on future failures."

git push

# 等 CI (5-10min) → 下 Artifact zip → KSU 装 → 重启
```

## 验证(装机后期望日志)
```
[lsm] BPF LSM active in kernel
[lsm] target limit_map id=N
[lsm] step3: create_ctrl_map
[lsm] step3: ctrl_map fd=N
[lsm] step3: ringbuf_map fd=N
[lsm] step4: parse_bpf_object
[lsm] step4: parsed bpf.o: NN insns, NN relocs, btf=NNNN bytes
[lsm] step5: using attach_btf_id=0 (kernel auto-infer)
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
[sched] BPF LSM guard ACTIVE
```

如果某 step 之后没有期望的下一行 → 那个 step 失败了,告诉我崩点。

## 包含
- daemon/hotspotd/lsm/hnc_lsm_loader.c (新版,删 BTF parser + 加诊断)
- bpf/hnc_limit_map_guard.bpf.o (预编译,跟之前一样,作 fallback 用)
