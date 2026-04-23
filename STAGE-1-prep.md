# v5.0 → v5.1 libbpf 路线 — Stage 1: 准备 third_party 源码

直接把 libbpf + libelf + zlib 源码作为 git submodule 进仓库,
绕过所有 Linux 发行版/Termux/NDK 的环境差异,CI 只需要 NDK 编译。

## 在 ~/hnc-v5 跑

```sh
cd ~/hnc-v5
mkdir -p third_party
cd third_party

# 1. libbpf v1.4.0
git submodule add -b v1.4.0 https://github.com/libbpf/libbpf.git libbpf

# 2. libelf - 用 android-libelf (Andrey Vagin 的 portable fork)
# 这个 fork 改了 elf64 endian 等 API, 适配 bionic
git submodule add https://github.com/avagin/android-libelf.git libelf
# 备选: 如果上面的 repo 死了, 用 elftoolchain
# git submodule add https://github.com/elftoolchain/elftoolchain.git elftoolchain

# 3. zlib v1.3
git submodule add -b v1.3 https://github.com/madler/zlib.git zlib

cd ~/hnc-v5
git submodule update --init --recursive
git status
git add .gitmodules third_party/
git commit -m "v5.1 libbpf migration prep: add libbpf + libelf + zlib as submodules"
git push

# 验证
ls -la third_party/libbpf/src/  # 应该有 libbpf.c, btf.c, libbpf_internal.h 等
ls -la third_party/libelf/      # 应该有 libelf 头 + .c
ls -la third_party/zlib/        # 应该有 zlib.h, deflate.c 等
```

跑完上面命令后告诉我:
1. 三个 submodule 都 add 成功了吗?
2. `third_party/libbpf/src/` 下有几个 .c 文件?(应该 ~10 个)
3. `third_party/libelf/` 下结构(给我 ls 输出)?

下一步我会基于实际仓库结构写 build.sh 集成 patch + 新 loader.c。
