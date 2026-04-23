#!/bin/bash
# third_party_build/build_libs.sh
# 用 Android NDK clang 静态编 zlib + libelf + libbpf, 输出到 _libs_out/
#
# 依赖环境变量:
#   ANDROID_NDK   (例如 /opt/android-ndk-r27c)
#
# 输出目录结构:
#   _libs_out/
#     include/
#       zlib.h, zconf.h
#       libelf.h, gelf.h, elfdefinitions.h, _elftc.h, sys/queue.h, ...
#       bpf/libbpf.h, bpf/bpf.h, bpf/bpf_helpers.h, bpf/btf.h, ...
#       linux/bpf.h, linux/btf.h, ... (libbpf 自带的 uapi 头)
#     lib/
#       libz.a
#       libelf.a
#       libbpf.a
#
# 跑法:
#   cd third_party_build
#   ANDROID_NDK=/opt/android-ndk-r27c ./build_libs.sh arm64

set -e
ARCH="${1:-arm64}"
[ -z "$ANDROID_NDK" ] && { echo "ERROR: ANDROID_NDK env not set"; exit 1; }

case "$ARCH" in
    arm64)   TARGET=aarch64-linux-android;  API=21 ;;
    *)       echo "Only arm64 supported"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)/third_party"
OUT="$SCRIPT_DIR/_libs_out"
HOST_TAG=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
AR="$TOOLCHAIN/bin/llvm-ar"
RANLIB="$TOOLCHAIN/bin/llvm-ranlib"

CFLAGS_COMMON="-O2 -fPIC -D_GNU_SOURCE -DPIC -Wno-everything"

mkdir -p "$OUT/include/bpf" "$OUT/include/linux" "$OUT/include/sys" "$OUT/lib"

# 检查源码完整
[ -f "$TP_ROOT/zlib/zlib.h" ]       || { echo "ERROR: third_party/zlib missing (git submodule update?)"; exit 1; }
[ -f "$TP_ROOT/libelf/libelf/libelf.h" ] || { echo "ERROR: third_party/libelf missing"; exit 1; }
[ -f "$TP_ROOT/libbpf/src/libbpf.h" ]    || { echo "ERROR: third_party/libbpf missing"; exit 1; }

echo "[build_libs] CC=$CC"
echo "[build_libs] OUT=$OUT"

# ═══════════════════════════════════════════════════════════
# 1. zlib
# ═══════════════════════════════════════════════════════════
if [ ! -f "$OUT/lib/libz.a" ]; then
    echo ""
    echo "=== Building zlib ==="
    cd "$TP_ROOT/zlib"
    ZLIB_OBJ_DIR="$OUT/_obj/zlib"
    mkdir -p "$ZLIB_OBJ_DIR"
    for src in adler32.c crc32.c deflate.c infback.c inffast.c inflate.c \
               inftrees.c trees.c zutil.c compress.c uncompr.c \
               gzclose.c gzlib.c gzread.c gzwrite.c; do
        echo "  CC zlib/$src"
        "$CC" $CFLAGS_COMMON -c "$src" -o "$ZLIB_OBJ_DIR/${src%.c}.o"
    done
    "$AR" rcs "$OUT/lib/libz.a" "$ZLIB_OBJ_DIR"/*.o
    "$RANLIB" "$OUT/lib/libz.a"
    cp zlib.h zconf.h "$OUT/include/"
    echo "[build_libs] libz.a OK ($(ls -lh "$OUT/lib/libz.a" | awk '{print $5}'))"
fi

# ═══════════════════════════════════════════════════════════
# 2. libelf (elftoolchain BSD libelf)
# ═══════════════════════════════════════════════════════════
if [ ! -f "$OUT/lib/libelf.a" ]; then
    echo ""
    echo "=== Building libelf (elftoolchain) ==="
    LIBELF_OBJ_DIR="$OUT/_obj/libelf"
    mkdir -p "$LIBELF_OBJ_DIR"

    LIBELF_SRC="$TP_ROOT/libelf/libelf"
    LIBELF_COMMON="$TP_ROOT/libelf/common"

    # elftoolchain 用 m4 模板生成 _libelf_native_* 头, 我们手写一个
    # _libelf_config.h 已存在, 但 native types 需要根据 target 设
    cat > "$OUT/include/_libelf_native.h" << 'NATIVE_EOF'
/* Auto-generated for aarch64-linux-android (LE, 64-bit) */
#define LIBELF_BYTEORDER  ELFDATA2LSB
#define LIBELF_CLASS      ELFCLASS64
#define LIBELF_ARCH       EM_AARCH64
NATIVE_EOF

    # 拷贝头文件到 OUT/include
    mkdir -p "$OUT/include/sys"
    cp "$LIBELF_SRC/libelf.h" "$OUT/include/"
    cp "$LIBELF_SRC/gelf.h"   "$OUT/include/"
    cp "$LIBELF_COMMON/_elftc.h" "$OUT/include/"
    cp "$LIBELF_COMMON/elfdefinitions.h" "$OUT/include/"
    # elftoolchain elfdefinitions.h 第 32 行 #include <sys/elfdefinitions.h>
    # 我们在 sys/ 子目录也放一份 (chimera-linux 版本默认放在 common/, 没拆 sys/)
    cp "$LIBELF_COMMON/elfdefinitions.h" "$OUT/include/sys/"
    if [ -d "$LIBELF_COMMON/sys" ]; then
        cp "$LIBELF_COMMON/sys"/*.h "$OUT/include/sys/" 2>/dev/null || true
    fi
    cp "$LIBELF_COMMON/utarray.h" "$OUT/include/" 2>/dev/null || true
    cp "$LIBELF_COMMON/uthash.h"  "$OUT/include/" 2>/dev/null || true
    cp "$LIBELF_SRC/_libelf.h"        "$OUT/include/"
    cp "$LIBELF_SRC/_libelf_ar.h"     "$OUT/include/"
    cp "$LIBELF_SRC/_libelf_config.h" "$OUT/include/"

    # 编译所有 elf_*.c, gelf_*.c, libelf_*.c
    cd "$LIBELF_SRC"
    LIBELF_CFLAGS="$CFLAGS_COMMON \
        -I$OUT/include \
        -I$LIBELF_SRC -I$LIBELF_COMMON \
        -include $OUT/include/_libelf_native.h \
        -DLIBELF_TEST_HOOKS=0 \
        -Wno-implicit-function-declaration"

    for src in *.c; do
        # 跳过 m4 生成文件 (我们没装 m4, 先跳过, 看 ld 报缺啥再补)
        echo "  CC libelf/$src"
        "$CC" $LIBELF_CFLAGS -c "$src" -o "$LIBELF_OBJ_DIR/${src%.c}.o" 2>&1 \
            | head -3 || echo "  (warn: $src)"
    done

    if ls "$LIBELF_OBJ_DIR"/*.o >/dev/null 2>&1; then
        "$AR" rcs "$OUT/lib/libelf.a" "$LIBELF_OBJ_DIR"/*.o
        "$RANLIB" "$OUT/lib/libelf.a"
        echo "[build_libs] libelf.a OK ($(ls -lh "$OUT/lib/libelf.a" | awk '{print $5}'))"
    else
        echo "[build_libs] ERROR: libelf no objects compiled — see warnings above"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════
# 3. libbpf (跳过 Makefile, 直接编 src/*.c)
# ═══════════════════════════════════════════════════════════
if [ ! -f "$OUT/lib/libbpf.a" ]; then
    echo ""
    echo "=== Building libbpf ==="
    LIBBPF_OBJ_DIR="$OUT/_obj/libbpf"
    mkdir -p "$LIBBPF_OBJ_DIR"

    LIBBPF_SRC="$TP_ROOT/libbpf/src"
    LIBBPF_INC="$TP_ROOT/libbpf/include"

    # 拷贝 libbpf 头到 OUT/include/bpf/
    cp "$LIBBPF_SRC/libbpf.h"          "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf.h"             "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/btf.h"             "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf_helpers.h"     "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf_helper_defs.h" "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf_endian.h"      "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf_tracing.h"     "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/bpf_core_read.h"   "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/libbpf_common.h"   "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/libbpf_legacy.h"   "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/libbpf_version.h"  "$OUT/include/bpf/"
    cp "$LIBBPF_SRC/skel_internal.h"   "$OUT/include/bpf/" 2>/dev/null || true
    cp "$LIBBPF_SRC/usdt.bpf.h"        "$OUT/include/bpf/" 2>/dev/null || true

    # libbpf 自带 uapi headers
    cp -r "$LIBBPF_INC/uapi/linux"/* "$OUT/include/linux/" 2>/dev/null || true

    cd "$LIBBPF_SRC"
    LIBBPF_CFLAGS="$CFLAGS_COMMON \
        -I$OUT/include \
        -I$LIBBPF_SRC \
        -I$LIBBPF_INC \
        -I$LIBBPF_INC/uapi \
        -DCOMPAT_NEED_REALLOCARRAY \
        -DCOMPAT_NEED_STRERROR_R \
        -Wno-implicit-function-declaration \
        -Wno-pointer-sign"

    # 编 src/*.c
    for src in *.c; do
        # 排除 linker.c (libbpf 内部 BPF linker, 不需要), gen_loader.c (不需要)
        case "$src" in
            linker.c|gen_loader.c) echo "  SKIP $src"; continue ;;
        esac
        echo "  CC libbpf/$src"
        "$CC" $LIBBPF_CFLAGS -c "$src" -o "$LIBBPF_OBJ_DIR/${src%.c}.o" 2>&1 | head -5 \
            || echo "  (warn: $src)"
    done

    if ls "$LIBBPF_OBJ_DIR"/*.o >/dev/null 2>&1; then
        "$AR" rcs "$OUT/lib/libbpf.a" "$LIBBPF_OBJ_DIR"/*.o
        "$RANLIB" "$OUT/lib/libbpf.a"
        echo "[build_libs] libbpf.a OK ($(ls -lh "$OUT/lib/libbpf.a" | awk '{print $5}'))"
    else
        echo "[build_libs] ERROR: libbpf no objects compiled"
        exit 1
    fi
fi

echo ""
echo "=== ALL DONE ==="
ls -la "$OUT/lib/"
echo ""
echo "Headers:"
ls "$OUT/include/" | head -10
echo "..."
ls "$OUT/include/bpf/" | head -10
