#!/bin/sh
# 从 docs/logo.svg 重新生成所有图标资产
#   - docs/logo.png / logo-dark.png  README 用（透明底，深浅双版本）
#   - docs/app-icon.svg              自动生成：浅色圆角底板 + logo 线条（勿手改）
#   - Resources/AppIcon.icns         App 图标
# 依赖: npx sharp-cli（libvips 内置 SVG 渲染，保留透明背景）
set -e
cd "$(dirname "$0")/.."

sed 's/#171717/#e5e5e5/g' docs/logo.svg > docs/logo-dark.svg
npx -y sharp-cli -i docs/logo.svg      -o docs/logo.png      --density 180
npx -y sharp-cli -i docs/logo-dark.svg -o docs/logo-dark.png --density 180

python3 - <<'PY'
import re
logo = open("docs/logo.svg").read()
g = re.search(r"<g .*?</g>", logo, re.S).group(0)
wrapper = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" fill="none">
  <title>ScreenRules app icon</title>
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#EFEFF2"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
  <svg x="144" y="150" width="736" height="736" viewBox="0 0 512 512" fill="none">{g}</svg>
</svg>
'''
open("docs/app-icon.svg", "w").write(wrapper)
PY
npx -y sharp-cli -i docs/app-icon.svg -o /tmp/app-icon.png --density 90

ICONSET=/tmp/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
sips -z 16 16   /tmp/app-icon.png --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32   /tmp/app-icon.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32   /tmp/app-icon.png --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64   /tmp/app-icon.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128 /tmp/app-icon.png --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256 /tmp/app-icon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 /tmp/app-icon.png --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512 /tmp/app-icon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 /tmp/app-icon.png --out "$ICONSET/icon_512x512.png"    >/dev/null
cp /tmp/app-icon.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> icons regenerated"
