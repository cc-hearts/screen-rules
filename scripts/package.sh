#!/bin/sh
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.1}"
echo "==> Packaging ScreenRules v${VERSION} (Universal: arm64 + x86_64)..."

# 编译两个架构
swift build -c release --triple arm64-apple-macosx
swift build -c release --triple x86_64-apple-macosx

APP="ScreenRules.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 合并生成通用二进制 (Universal Binary)
lipo -create -output "$APP/Contents/MacOS/ScreenRules" \
  .build/arm64-apple-macosx/release/ScreenRules \
  .build/x86_64-apple-macosx/release/ScreenRules

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 动态同步 Info.plist 中的版本号
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true

# 签名
if security find-identity -v -p codesigning 2>/dev/null | grep -q "ScreenRules Dev"; then
    codesign --force --deep --sign "ScreenRules Dev" --identifier com.carl.screenrules "$APP" 2>/dev/null || true
    echo "==> signed with: ScreenRules Dev"
else
    codesign --force --deep --sign - --identifier com.carl.screenrules "$APP" 2>/dev/null || true
    echo "==> signed ad-hoc"
fi

# 打包 DMG
echo "==> Creating DMG..."
DMG_NAME="ScreenRules-${VERSION}.dmg"
DMG_ROOT="/tmp/dmg_screenrules"
rm -rf "$DMG_ROOT" && mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_NAME"
hdiutil create -volname "ScreenRules" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_NAME"
rm -rf "$DMG_ROOT"

# 打包 ZIP (保留 macOS 资源分支与权限)
echo "==> Creating ZIP..."
ZIP_NAME="ScreenRules-${VERSION}.zip"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP" "$ZIP_NAME"

# 生成 SHA256 校验和
echo "==> Generating SHA256 checksums..."
shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > "ScreenRules-${VERSION}-sha256.txt"

echo "==> Done!"
echo "    - $DMG_NAME"
echo "    - $ZIP_NAME"
echo "    - ScreenRules-${VERSION}-sha256.txt"
