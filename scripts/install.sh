#!/bin/bash
# 把构建好的 cleo.prx 安装到 PPSSPP，并补齐配置
#
# 用法:
#   ./scripts/install.sh                     # 使用 build/out/cleo.prx
#   ./scripts/install.sh /path/to/cleo.prx   # 使用指定 PRX
#   CLEO_DIR=... ./scripts/install.sh        # 指定 CLEO 目录（便携版/Android 等）
set -e

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PRX="${1:-$HERE/build/out/cleo.prx}"
DEST="${CLEO_DIR:-$HOME/.config/ppsspp/PSP/PLUGINS/cleo}"

if [ ! -f "$PRX" ]; then
	echo "找不到 PRX: $PRX" >&2
	echo "请先编译（build/build-cleo.sh），或直接使用 Releases 里的 zip 包。" >&2
	exit 1
fi

if [ ! -d "$DEST" ]; then
	echo "找不到 CLEO 目录: $DEST" >&2
	echo "便携版/其他平台请用 CLEO_DIR 指定，例如：" >&2
	echo "  CLEO_DIR=/path/to/PPSSPP/PSP/PLUGINS/cleo $0 \"$PRX\"" >&2
	exit 1
fi

if [ -f "$DEST/cleo.prx" ] && [ ! -f "$DEST/cleo.prx.bak-2.0.2" ]; then
	cp "$DEST/cleo.prx" "$DEST/cleo.prx.bak-2.0.2"
	echo "已备份原 cleo.prx -> cleo.prx.bak-2.0.2"
fi

cp "$PRX" "$DEST/cleo.prx"
echo "已安装 cleo.prx ($(stat -c %s "$DEST/cleo.prx") 字节)"

if [ -f "$DEST/cleo.ini" ]; then
	echo "cleo.ini 已存在，保留原配置"
else
	cp "$HERE/config/cleo.ini" "$DEST/cleo.ini"
	echo "已写入 cleo.ini（text_offset=-2，仅 ULJM05297 生效）"
fi

if [ -f "$DEST/plugin.ini" ] && ! grep -q "^ULJM05297" "$DEST/plugin.ini"; then
	sed -i '/^\[games\]/a ULJM05297 = true' "$DEST/plugin.ini"
	echo "已向 plugin.ini 加入 ULJM05297 = true"
fi

echo
echo "安装完成。启动 PPSSPP，游戏内按两次 Start 打开 CLEO 菜单。"
echo "验证: 查看 $DEST/cleo.log，应出现 text_offset: -2 与 launch_scripts success"
