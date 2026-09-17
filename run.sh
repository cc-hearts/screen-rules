#!/bin/sh
# 一键：构建 + 重启 ScreenRules
set -e
cd "$(dirname "$0")"
./build.sh
pkill -x ScreenRules 2>/dev/null || true
sleep 1
open ScreenRules.app
echo "==> ScreenRules 已启动（菜单栏右上角找双显示器图标）"
