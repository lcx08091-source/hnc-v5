# HNC v5.1 libbpf 改造 — Stage 2 patch

## 文件
1. `third_party_build/build_libs.sh` (205 行) — NDK 静态编 zlib + libelf + libbpf,输出到 `_libs_out/`
2. `third_party_build/.gitignore` — 忽略编译产物
3. `daemon/hotspotd/build.sh` (132 行) — hotspotd 编译时链接 3 个静态库
4. `.github/workflows/build.yml` (141 行) — CI 加 submodule init + build_libs step

## 装机步骤(在 `~/hnc-v5`)

```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-libbpf-stage2.zip .
unzip -o HNC-v5_1-libbpf-stage2.zip
rm HNC-v5_1-libbpf-stage2.zip

# 检查
ls -la third_party_build/build_libs.sh         # 应该 +x
ls -la daemon/hotspotd/build.sh                # 应该 +x
ls -la .github/workflows/build.yml

# Commit + push
git add -A
git status      # 确认含: third_party_build/, .gitmodules, daemon/hotspotd/build.sh,
                #         daemon/hotspotd/lsm/hnc_lsm_loader.c (Stage 1 unzip 时已加),
                #         .github/workflows/build.yml

git commit -m "v5.1: libbpf static-link migration

Replaces 800-line hand-rolled sys_bpf loader with libbpf API
(bpf_object__open_file + load + attach_lsm + ring_buffer__poll).

Build chain:
  third_party/{libbpf,libelf,zlib} as git submodules
  third_party_build/build_libs.sh: NDK clang -> static .a libs
  daemon/hotspotd/build.sh: links libbpf.a + libelf.a + libz.a (~700KB
    increase to hotspotd binary, acceptable)
  .github/workflows/build.yml: + submodules:recursive + build_libs step

This delegates BTF sanitization, .rel.BTF resolution, CO-RE relocation
to libbpf, escaping the hand-rolled sys_bpf dead-end (BPF_BTF_LOAD
EINVAL/ENOSPC encountered in beta.4 hotfix1-5)."

git push
```

## CI 第一次跑大概 8-12 分钟(要编 ~100 个 .c 静态库)

后续构建 build_libs.sh 会跳过(`if [ ! -f libbpf.a ]`)→ 几秒
但 GitHub Actions runner 每次新机器,实际每次 CI 都会重编。

## 期望失败 + 应对(按可能性排)

**1. libelf 编译失败** — elftoolchain 用了一些 GNU 扩展可能 Bionic 缺
   - 现象:`warn: elf_xxx.c` 一堆然后 ar 报 no objects
   - 应对:贴 build_libs 输出给我,我加 -include shim.h

**2. libbpf 编译失败** — 类似 GNU 扩展
   - 现象:同上
   - 应对:同上

**3. hotspotd 链接失败** — symbol undef
   - 现象:`undefined reference to 'mempcpy'` / `argp_parse` / `obstack_*`
   - 应对:加 missing.c shim 或者排除某些 libelf source

**4. hotspotd 链接成功但 LSM init 失败** — libbpf 报错
   - 现象:`[libbpf] xxx error` 在日志里
   - 应对:基于 libbpf 报的具体错改 BPF program 或 loader

不管哪种,贴 CI build log(失败那一段)+ 装机日志,我快速迭代。

## 不会破坏的事
- beta.3 scheduler 周期重探仍生效(不依赖 LSM)
- LSM 失败时 graceful 降级到 passive 模式,业务 100% 正常
- watchdog / hnc_httpd / tc_netlink 全部不变

## 涉及风险(可控)
- hotspotd binary 大小 130KB → ~700KB(可接受)
- CI 第一次 build 时间长(可接受,后续艺术家 GitHub cache 加速)
- libelf cross-compile 第一次必踩坑(预期 1-2 轮 hotfix)
