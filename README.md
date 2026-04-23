# v5.1 libbpf Stage 2 - Fix 3: include <elf.h> in _libelf_native.h

## 问题(Gemini 抓到)
fix2 后 elfdefinitions.h 被注入,但新错误:
```
libelf_xlate.c:59:18: error: use of undeclared identifier 'ELFDATANONE'
libelf_xlate.c:62:19: error: use of undeclared identifier 'ELFDATA2LSB'
libelf_xlate.c:62:46: error: use of undeclared identifier 'ELFDATA2MSB'
```

`ELFDATA*` / `ELFCLASS*` / `EM_*` 是标准 ELF 常量(在系统 `<elf.h>` 里),
不在 elftoolchain 的 elfdefinitions.h 里(它定义的是 *Elf32_Ehdr*, *Elf32_Sym*
这种 type,不是常量宏)。

我之前自动生成的 _libelf_native.h 用了 `ELFDATA2LSB` 但**没先 include <elf.h>**,
当 -include _libelf_native.h 注入时,编译器看到 ELFDATA2LSB 还不知道是啥。

## 修
_libelf_native.h heredoc 加一行 `#include <elf.h>`(用 Bionic NDK 自带的标准
ELF 头文件提供所有常量)。

## 装
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-stage2-fix3.zip .
unzip -o HNC-v5_1-stage2-fix3.zip
rm HNC-v5_1-stage2-fix3.zip
git add -A
git commit -m "v5.1 stage2 fix3: #include <elf.h> in _libelf_native.h

Bionic NDK provides standard ELFDATA*/ELFCLASS*/EM_* constants in
<elf.h>. Our generated _libelf_native.h used ELFDATA2LSB without
first including <elf.h>, causing undeclared identifier errors when
the file was -include'd. Diagnosis credit: Gemini peer review."
git push
```

## 期望下一轮
libelf_xlate.c 应该过, 然后剩下 56 个 .c 应该大部分都过
(libelf 整体不太用 GNU 扩展, 主要是 ELF parsing)。

如果 libelf 全过, 接着 libbpf 编译开始 — libbpf 用了一堆 GNU 扩展
(mempcpy, argp.h, obstack), 大概率有 5-10 个 .c 失败需要 shim。
继续贴 CI log。
