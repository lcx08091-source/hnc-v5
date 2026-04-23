# v5.1 FINAL fix5 — bump Android API 21 → 28

## 问题
fix4 让 gen_loader.c 编进 libbpf.a, 但链接 hotspotd 时:
```
ld.lld: error: undefined symbol: fmemopen
    referenced by libbpf.c
ld.lld: error: undefined symbol: __libelf_next_arhdr_wrlock
    referenced by libelf.a
```

## 原因
- **fmemopen**: Android Bionic 从 **API 23** 才提供(参考 bionic status)
- **__libelf_next_arhdr_wrlock**: JiaHuann 预编译 libelf.a 时用了 API 28+, 
  包含 pthread rwlock API(需要 API 24+),我们 API 21 的 linker 找不到符号

两个问题都来自 `build_libs.sh` + `daemon/hotspotd/build.sh` 里 `API=21` 太低。

## 修
两个文件都改 `API=21 → API=28`(Android 9, 2018+ 设备全支持,你的 Android 16 远高于)。

## 装(含手动改 daemon/hotspotd/build.sh)

```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-FINAL-fix5.zip .
unzip -o HNC-v5_1-FINAL-fix5.zip
rm HNC-v5_1-FINAL-fix5.zip

# build_libs.sh 已被 zip 覆盖为 API=28
# daemon/hotspotd/build.sh 需要手改
sed -i 's/API=21/API=28/g' daemon/hotspotd/build.sh

# 验证
grep "API=" third_party_build/build_libs.sh daemon/hotspotd/build.sh

git add -A
git commit -m "v5.1 FINAL fix5: bump Android API 21 -> 28

fmemopen (bionic) introduced at API 23, __libelf_next_arhdr_wrlock
(from JiaHuann libelf.a built at API 28) needs pthread rwlock at
API 24+. API 21 is too low; bump both build_libs.sh and hotspotd's
build.sh to API 28. Our target device is Android 16 (API 36), no
compatibility issue."
git push
```

## 预期
这次 hotspotd 链接应该过, libbpf.a + libelf.a + libz.a 都能完整引用。
然后剩下就是 BPF object 编译 + pack zip + artifact 上传。

## 万一还有别的 undefined symbol
libbpf v1.8 用了一些新 syscall (close_range, memfd_create 等),需要
API 29-30 才有。如果 fix5 还报 undef, 我给 fix6 bump API 到 30。
