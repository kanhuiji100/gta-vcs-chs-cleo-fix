#!/bin/bash
# 从上游源码构建修复版 cleo.prx
#
# 用法:
#   PSPDEV=/path/to/pspdev ./build/build-cleo.sh              # 自动拉取上游 + 打补丁 + 编译
#   PSPDEV=/path/to/pspdev ./build/build-cleo.sh /path/repo   # 使用已存在的上游仓库副本
#   OUT=/tmp/out PSPDEV=... ./build/build-cleo.sh             # 指定输出目录
#
# 需要: pspdev 工具链 (psp-gcc / psp-prxgen / psp-config / psp-build-exports)
#       https://github.com/pspdev/pspdev/releases -> pspdev-ubuntu-latest-x86_64.tar.gz
#       curl, tar, patch
set -e

HERE="$(cd "$(dirname "$0")/.." && pwd)"
: "${PSPDEV:?请设置 PSPDEV，指向 pspdev 工具链目录（含 bin/psp-gcc 的那一层）}"
export PATH="$PSPDEV/bin:$PATH"

PSPSDK="$("$PSPDEV/bin/psp-config" --pspsdk-path)"
OUT="${OUT:-$HERE/build/out}"

UPSTREAM_TARBALL="https://codeload.github.com/cleolibrary/GTALCS.GTAVCS.PSP.CLEO/tar.gz/refs/heads/main"
INJECTOR_TARBALL="https://codeload.github.com/ThirteenAG/injector/tar.gz/refs/heads/master"

SRC_REPO="${1:-}"
if [ -z "$SRC_REPO" ]; then
	WORK="$HERE/.build/upstream"
	echo "==> 拉取上游源码到 $WORK"
	rm -rf "$WORK"; mkdir -p "$WORK"
	curl -sL --max-time 120 "$UPSTREAM_TARBALL" | tar xz -C "$WORK" --strip-components=1

	echo "==> 应用补丁"
	patch -p1 -d "$WORK" < "$HERE/patches/cleo-vcs-chs.patch"

	echo "==> 拉取 injector 依赖"
	rm -rf "$WORK/external/injector"; mkdir -p "$WORK/external/injector"
	curl -sL --max-time 120 "$INJECTOR_TARBALL" | tar xz -C "$WORK/external/injector" --strip-components=1

	SRC_REPO="$WORK"
fi

SRC="$SRC_REPO/source"
INJ="$SRC_REPO/external/injector/include"

if [ ! -f "$INJ/psp/patterns.c" ]; then
	echo "缺少 $INJ/psp/patterns.c —— 请确认源码目录完整（含 external/injector 子模块）" >&2
	exit 1
fi

rm -rf "$OUT"; mkdir -p "$OUT"; cd "$OUT"

COMMON="-I$SRC -I$PSPDEV/psp/include -I$PSPSDK/include -I$INJ \
-DPSP_HOOK_RAM_END=0x0DD00000 -DPSP -DMEM_CUSTOM_TOTAL_SIZE=16384 -DPSP_GAME_ABI_COMPAT \
-D_PSP_FW_VERSION=600 -Os -G0 -Wall -mpreferred-stack-boundary=4 -mabi=eabi -fno-exceptions -fno-rtti"

FILES="main.cpp utils.cpp text.cpp libres.cpp armhook.cpp touch.cpp ui.cpp plugins.cpp \
pattern.cpp core.cpp mutex.cpp strutils.cpp memutils.cpp psplang.cpp"

OBJS=""
for f in $FILES; do
	echo "[CXX] $f"
	psp-g++ $COMMON -c "$SRC/$f" -o "${f%.cpp}.o"
	OBJS="$OBJS ${f%.cpp}.o"
done

for c in "$INJ/psp/memalloc.c" "$INJ/psp/patterns.c" "$SRC/module-memory.c"; do
	echo "[CC] $(basename "$c")"
	psp-gcc $COMMON -c "$c" -o "$(basename "${c%.c}").o"
	OBJS="$OBJS $(basename "${c%.c}").o"
done

echo "[EXP]"
psp-build-exports -b "$SRC/exports.exp" > cleo_exports.c
psp-gcc $COMMON -c cleo_exports.c -o cleo_exports.o

echo "[LD]"
psp-gcc -L"$PSPDEV/psp/lib" -L"$PSPSDK/lib" \
	-specs="$PSPSDK/lib/prxspecs" -Wl,-q,-T"$PSPSDK/lib/linkfile.prx" -Wl,-zmax-page-size=128 \
	$OBJS cleo_exports.o -lstdc++ -lm \
	-lpspdebug -lpspdisplay -lpspge -lpspctrl -lpspnet -lpspnet_apctl \
	-o cleo.elf
psp-fixup-imports cleo.elf

echo "[PRX]"
psp-prxgen cleo.elf cleo.prx

echo
echo "完成: $OUT/cleo.prx ($(stat -c %s "$OUT/cleo.prx") 字节)"
echo "参考值: 523,514 字节 / md5 b229cffcb0f837d0b3dbac2ccd701242"
