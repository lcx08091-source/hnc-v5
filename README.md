# v5.1 libbpf FINAL fix4 — 保留 gen_loader.c

## 进展
FINAL 版本 CI 跑通了 build_libs (libelf.a + libz.a + libbpf.a 都编出来)!
只在链接 hotspotd 时报 undefined symbol `bpf_gen__map_create`。

## 原因
之前 build_libs.sh SKIP 了 `gen_loader.c`,但 libbpf.c 内部的
`bpf_object__create_map` 调用 `bpf_gen__map_create` (在 gen_loader.c 里)。
SKIP 后 libbpf.a 里找不到这个 symbol, 链接失败。

## 修
只 SKIP `linker.c`(那个是 bpf-linker util,跟运行无关),保留
`gen_loader.c`(bpf_object 加载路径一部分,必需)。

## 装
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-FINAL-fix4.zip .
unzip -o HNC-v5_1-FINAL-fix4.zip
rm HNC-v5_1-FINAL-fix4.zip
git add -A
git commit -m "v5.1 FINAL fix4: keep gen_loader.c in libbpf.a

Previous SKIP gen_loader.c caused libbpf.c's bpf_object__create_map
to reference undefined bpf_gen__map_create at hotspotd link stage.
Only SKIP linker.c (bpf-linker util, not runtime)."
git push
```

## 预期
这次 CI 跑 hotspotd 链接应该过。剩下的问题可能:
- BPF 对象编译失败 (clang -target bpf)
- 无关大局的 warnings
