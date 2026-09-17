#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=ScreenRules.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenRules "$APP/Contents/MacOS/ScreenRules"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 优先用固定的自签名证书（权限授权跨构建保留）；没有就退回临时签名（每次构建权限会失效）
if security find-identity -v -p codesigning | grep -q "ScreenRules Dev"; then
    codesign --force --deep --sign "ScreenRules Dev" --identifier com.carl.screenrules "$APP"
    echo "==> signed with: ScreenRules Dev"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
    echo "==> signed ad-hoc (注意：每次重建后辅助功能授权会失效)"
fi
echo "==> built: $(pwd)/$APP"
echo "==> run:   open $APP"
