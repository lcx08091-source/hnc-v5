# v5.1 FINAL fix8 — ZSTD/BZ2 stubs for libelf

## 问题
fix7 解决 crc32, 现在报:
```
ld.lld: error: undefined symbol: ZSTD_createCCtx (+ 4 more)
    referenced by elf_compress.c in libelf.a
```

Termux libelf-static 0.193 编译时启用了 zstd/bz2/lzma 压缩支持,但:
1. Termux 没有 `libzstd`/`libbz2-static` 等包名 (pkg search 证实)
2. libbpf 从不加载 COMPRESSED ELF section (BPF .o 不用)
3. 所以这些 ZSTD 函数 runtime 永远不会被调用

## 修
写 `compat_stubs.c` — 空实现 ZSTD_createCCtx / ZSTD_freeCCtx /
ZSTD_compressStream2 / ZSTD_decompress / BZ2_* 等函数,内部 abort()
(runtime 不会跑到这)。让 linker 有 symbol 可以 resolve。

把 `lsm/compat_stubs.c` 加到 hotspotd 的 build.sh SRCS 列表。

## 装
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-FINAL-fix8.zip .
unzip -o HNC-v5_1-FINAL-fix8.zip
rm HNC-v5_1-FINAL-fix8.zip

# 把 compat_stubs.c 加到 build.sh 的 SRCS 
# 找 SRCS="hotspotd.c ..." 那行,在末尾加 lsm/compat_stubs.c
sed -i 's|lsm/hnc_lsm_loader.c"|lsm/hnc_lsm_loader.c lsm/compat_stubs.c"|' daemon/hotspotd/build.sh

# 验证
grep "lsm/" daemon/hotspotd/build.sh | head -3

git add -A
git commit -m "v5.1 FINAL fix8: stub out ZSTD/BZ2 for libelf's elf_compress.c

Termux libelf-static was built with compression support, but Termux
has no libzstd-static/libbz2-static packages. libbpf doesn't load
compressed ELF sections anyway (BPF objects are plain), so these
functions are never called at runtime.

compat_stubs.c provides abort()-on-call stubs for:
  ZSTD_createCCtx/freeCCtx/compressStream2/decompress/isError
  BZ2_bzBuffToBuff{Compress,Decompress}

Linker now has symbols to resolve; runtime safety guaranteed by
our BPF .o files being uncompressed."
git push
```

## 如果 CI 报 "lzma undef"
说明还需要 liblzma stubs。告诉我具体的 undef symbol, 我加到 compat_stubs.c。
但 liblzma 被 libelf call 的概率更低。
