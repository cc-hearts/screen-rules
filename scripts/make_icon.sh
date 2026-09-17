#!/bin/sh
# 从 docs/logo.svg 重新生成所有图标资产（README PNG + App icns）
# 依赖: npx sharp-cli（libvips 内置 SVG 渲染，保留透明背景）
set -e
cd "$(dirname "$0")/.."

sed 's/#171717/#e5e5e5/g' docs/logo.svg > docs/logo-dark.svg
npx -y sharp-cli -i docs/logo.svg      -o docs/logo.png      --density 180
npx -y sharp-cli -i docs/logo-dark.svg -o docs/logo-dark.png --density 180

ICONSET=/tmp/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
sips -z 16 16   docs/logo.png --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   docs/logo.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   docs/logo.png --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   docs/logo.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 docs/logo.png --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 docs/logo.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 docs/logo.png --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 docs/logo.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 docs/logo.png --out "$ICONSET/icon_512x512.png"    >/dev/null
cp docs/logo.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> icons regenerated"
