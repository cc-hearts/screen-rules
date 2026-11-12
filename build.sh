#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=ScreenRules.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ScreenRules "$APP/Contents/MacOS/ScreenRules"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 签名走共享逻辑（与 scripts/package.sh 同一处，避免两边各写一遍而漂移）
sh "$(dirname "$0")/scripts/sign.sh" "$APP"
echo "==> built: $(pwd)/$APP"
echo "==> run:   open $APP"
