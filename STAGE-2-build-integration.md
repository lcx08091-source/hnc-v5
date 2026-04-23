# Stage 2 (我下一轮做): build.sh + .github/workflows/build.yml 改造

Stage 1 跑完, 你确认 third_party/ 三个 submodule 都到位 (尤其 libbpf/src/
有 ~10 个 .c) 后, 我会发 Stage 2 patch:

1. **修改 daemon/hotspotd/build.sh**:
   - 编译前先用 NDK clang 编 zlib.a → libelf.a → libbpf.a
   - hotspotd 链接时加 `-l:libbpf.a -l:libelf.a -l:libz.a`
   - 不再编 BPF 部分(改用 libbpf + bpf_object__load 处理)

2. **修改 .github/workflows/build.yml**:
   - 加 `git submodule update --init --recursive` step
   - 不需要 apt-get install libbpf-dev (CI 上没有, 我们自己编)

3. **可能微调 hnc_limit_map_guard.bpf.c**:
   - 用 libbpf 标准 SEC name + struct map 写法
   - 大多数情况下当前写法已 OK

预期效果:
- hotspotd binary 大小: 130KB → ~700KB (link in libbpf 600KB)
- LSM init 完整跑通, BTF sanitize / CO-RE 由 libbpf 处理
- 所有手撸路线踩的 BTF/.rel.BTF/CO-RE 坑直接消失

## Stage 1 完成度判断

跑完 Stage 1 后要告诉我:
1. `git submodule status` 输出
2. `find third_party/libbpf/src -name "*.c" | wc -l` 输出
3. `find third_party/libelf -name "*.c" | head -10` 输出
4. `ls third_party/zlib/*.c | wc -l` 输出

这 4 个数据告诉我 stage 2 该写什么编译命令。
