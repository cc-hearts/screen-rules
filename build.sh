#!/bin/sh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=ScreenRules.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenRules "$APP/Contents/MacOS/ScreenRules"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "==> built: $(pwd)/$APP"
echo "==> run:   open $APP"
