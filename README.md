# v5.1 libbpf Stage 2 - Fix 2: 强制注入 elfdefinitions.h

## 问题
fix1 后 sys/elfdefinitions.h 找到了, 但新错误:
```
libelf.h:233:1: error: unknown type name 'Elf32_Ehdr'
   233 | Elf32_Ehdr *elf32_getehdr(Elf *_elf);
```

elftoolchain 的 libelf.h 用 ELF types (Elf32_Ehdr 等) 但**自己不 #include**
elfdefinitions.h, 期望 user 在 source 里先 include。我们 build 时
ELF type 没注入到编译单元。

## 修
LIBELF_CFLAGS 加 `-include elfdefinitions.h`,强制每个 .c 编译头部
注入 ELF type 定义,等价于每个 .c 第一行加了 #include "elfdefinitions.h"。

顺手:把 head -3 截断去掉, 让 CI 显示完整 compiler error (失败时方便诊断)

## 装
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-stage2-fix2.zip .
unzip -o HNC-v5_1-stage2-fix2.zip
rm HNC-v5_1-stage2-fix2.zip
git add -A
git commit -m "v5.1 stage2 fix2: -include elfdefinitions.h forces ELF type injection

elftoolchain libelf.h declares functions returning Elf32_Ehdr etc
but doesn't itself include the type definitions, expecting user to
include them. -include CFLAG injects elfdefinitions.h into every TU."
git push
```

## 期望下一轮
libelf 53/57 编通,可能还有 4-5 个特殊 .c 失败 (用了 GNU 扩展)。
失败的 .c 文件如果不影响 libbpf 用到的核心功能, 可以从 .a 排除。
贴新的 CI build log 给我。
