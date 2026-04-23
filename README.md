# v5.1 libbpf Stage 2 - Fix 1: libelf sys/elfdefinitions.h missing

## 问题
CI build_libs 跑到 libelf_xlate.c 时报:
```
fatal error: 'sys/elfdefinitions.h' file not found
```

elftoolchain 的 elfdefinitions.h 第 32 行 `#include <sys/elfdefinitions.h>`,
但 chimera-linux 版本把这个文件放在 common/ 顶层(不在 common/sys/)。

## 修
build_libs.sh 加 `mkdir -p OUT/include/sys` 提前 + 显式拷一份
elfdefinitions.h 到 sys/ 子目录(让两个 include 路径都能找到)。

## 装
```sh
cd ~/hnc-v5
cp /sdcard/Download/HNC-v5_1-stage2-fix1.zip .
unzip -o HNC-v5_1-stage2-fix1.zip
rm HNC-v5_1-stage2-fix1.zip
git add -A
git commit -m "v5.1 stage2 fix1: libelf sys/elfdefinitions.h header path

elftoolchain elfdefinitions.h includes <sys/elfdefinitions.h> but
chimera-linux fork puts it in common/ root, not common/sys/. Copy
it to OUT/include/sys/ as well so both paths resolve."
git push
```

## 期望
CI 再次跑,这次 libelf 那段应该 53/53 文件全编通,接着 libbpf
开始编(libbpf 几乎肯定也有几个 GNU 扩展问题,等下一轮)。
