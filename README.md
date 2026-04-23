# HNC v5.0.0-beta.4 hotfix3: parse_bpf_object use-after-unmap 修复

## Root Cause(感谢 evaluation AI)
parse_bpf_object 末尾:
```c
munmap(elf, st.st_size);              // ELF 映射释放
*btf_size_out = sh_btf->sh_size;      // sh_btf 是野指针! → SEGV
```
`sh_btf` 指向 ELF section header table 内部,跟 mmap 区域共生。
`munmap` 后整块内存变成 PROT_NONE "洞",随后 `sh_btf->sh_size` 段错。

数学校验:
- mmap 基址(假设) = 0x7d85606000
- e_shoff = 0xa408
- .BTF section index = 7,Elf64_Shdr 大小 0x40
- offsetof(Elf64_Shdr, sh_size) = 0x20
- fault addr = 0x7d85606000 + 0xa408 + 7*0x40 + 0x20 = **0x7d856105e8** ✓

完美对上 tombstone fault addr。

之前我误以为 fault 在 [thread signal stack guard page] 是 stack overflow,
其实那是 munmap 之后内核标记区域刚好夹在两个 thread sigstack 中间,被
tombstone 解析器误认为 guard page。

## 修改
1. **parse_bpf_object**: 把 `sh_btf->sh_size` 提取到本地 `btf_size_local`
   *在* munmap 之前,然后再 munmap。这是 4 字符的修改。

2. **hotspotd.c main**: 装 SIGSEGV/SIGBUS/SIGABRT handler,任何段错先 write
   fault addr 到 stderr (= log file),再 raise default handler 让 tombstone
   照常生成。以后调试不用再翻 /data/tombstones/。

## 装机
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_0_0-beta4-hotfix3.zip .
unzip -o HNC-v5_0_0-beta4-hotfix3.zip
rm HNC-v5_0_0-beta4-hotfix3.zip
git add -A
git commit -m "v5.0.0-beta.4 hotfix3: parse_bpf_object use-after-unmap

Root cause (credit: evaluation AI):
  parse_bpf_object's final access to sh_btf->sh_size happens AFTER
  munmap(elf), making sh_btf a dangling pointer into freed mmap region.
  Tombstone fault addr 0x7d856105e8 = mmap_base + e_shoff +
  7*sizeof(Shdr) + offsetof(sh_size), exact match.

Fix: extract sh_size to local before munmap.

Bonus: install SIGSEGV/SIGBUS/SIGABRT handler in main() to log fault
address to stderr before tombstone, removing dependency on /data/tombstones/."
git push

# 等 CI → 装 → 重启 → 应该看到完整 LSM init 走完
```

## 期望日志(成功)
```
[lsm] BPF LSM active in kernel
[lsm] target limit_map id=3
[lsm] step3: create_ctrl_map
[lsm] step3: ctrl_map fd=10
[lsm] step3: ringbuf_map fd=11
[lsm] step4: parse_bpf_object
[lsm] step4: parsed bpf.o: NN insns, NN relocs, btf=NNNN bytes   ← 之前没出现的!
[lsm] step5: using attach_btf_id=0 (kernel auto-infer)
[lsm] step6: BPF_BTF_LOAD
[lsm] step6: prog_btf_fd=12
[lsm] step7: BPF_PROG_LOAD
... (期望 verifier OK 或 verifier log)
[lsm] step10: attach LSM
[lsm] step10: link_fd=N
[lsm] step11: start ringbuf consumer thread
[lsm] ACTIVE. protecting map_id=3 ifindex=22 hotspotd_pid=N
```

## 后续可能需要的事(evaluation AI 提到的 CO-RE)
我们 BPF 程序用了 BPF_CORE_READ 读 task_struct/files_struct 字段,
当前手撸 loader 只 BPF_BTF_LOAD 注入 .BTF, 没处理 .BTF.ext 的 CO-RE
重定位。这意味着 BPF 程序里的字段偏移是编译时 hardcode 的,跟真机
ColorOS 内核的实际偏移可能不一致 → verifier 拒绝 OR 静默读脏数据。

如果 hotfix3 装上后 step7 BPF_PROG_LOAD verifier log 报字段越界 / 类型
不匹配 / Invalid argument,需要进入下一阶段:引入 libbpf 静态链接
(NDK cross-compile libbpf + libelf + zlib),靠 libbpf 处理 CO-RE。

但 OPPO 用的 vmlinux.h 我们直接从真机 BTF dump 出来的,理论上字段
偏移跟运行时一致。BPF_CORE_READ 在 .BTF.ext 里只生成 relocation 信息,
verifier 看不到 .BTF.ext 时仍然按 hardcode 偏移走。**多半 OK**,但
这是个隐患,先看 hotfix3 实际验证。
