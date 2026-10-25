#!/bin/bash
# 恢复安装前的原版 CLEO 2.0.2
set -e

DEST="${CLEO_DIR:-$HOME/.config/ppsspp/PSP/PLUGINS/cleo}"

if [ ! -f "$DEST/cleo.prx.bak-2.0.2" ]; then
	echo "找不到备份: $DEST/cleo.prx.bak-2.0.2" >&2
	echo "可从上游重新下载原版: https://github.com/cleolibrary/GTALCS.GTAVCS.PSP.CLEO/releases" >&2
	exit 1
fi

cp "$DEST/cleo.prx.bak-2.0.2" "$DEST/cleo.prx"
echo "已恢复原版 cleo.prx (2.0.2)"

if [ -f "$DEST/cleo.ini" ]; then
	mv "$DEST/cleo.ini" "$DEST/cleo.ini.disabled"
	echo "已将 cleo.ini 改名为 cleo.ini.disabled（原版不读取它）"
fi
