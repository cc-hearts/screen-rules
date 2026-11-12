#!/bin/sh
set -e
cd "$(dirname "$0")/.."

VERSION="${1:-0.0.1}"
echo "==> Packaging ScreenRules v${VERSION} (Universal: arm64 + x86_64)..."

APP="ScreenRules.app"
BIN_OUT="$APP/Contents/MacOS/ScreenRules"

# 定位某个架构的 release 产物。SwiftPM 的产物布局随工具链变化：
#   老布局  .build/<triple>/release/<target>          (Xcode 15 及更早)
#   新布局  .build/out/Products/Release/<target>      (Swift 6 / Xcode 26+)
# 新布局下两个 triple 会写同一个路径，所以不能只靠路径区分架构。
find_release_binary() {
    triple="$1"
    for cand in \
        ".build/${triple}/release/ScreenRules" \
        ".build/out/Products/Release/ScreenRules"
    do
        if [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# 编译两个架构，尝试合成 universal
swift build -c release --triple arm64-apple-macosx
ARM_BIN="$(find_release_binary arm64-apple-macosx)" || ARM_BIN=""
swift build -c release --triple x86_64-apple-macosx
X86_BIN="$(find_release_binary x86_64-apple-macosx)" || X86_BIN=""

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ -n "$ARM_BIN" ] && [ -n "$X86_BIN" ] && [ "$ARM_BIN" != "$X86_BIN" ]; then
    # 两个独立产物 -> 真正的 universal
    echo "==> universal: $ARM_BIN + $X86_BIN"
    lipo -create -output "$BIN_OUT" "$ARM_BIN" "$X86_BIN"
else
    # 只剩一个产物（工具链把两个架构写到了同一路径）。此时不能假装它是
    # universal：最后编译的那个架构会覆盖前一个，产物可能不是本机架构
    # （Apple Silicon 上可能得到 x86_64-only，装上去根本跑不起来）。
    SINGLE="${ARM_BIN:-$X86_BIN}"
    HOST_ARCH="$(uname -m)"
    echo "==> note: toolchain produced one artifact only: $SINGLE"
    if lipo -info "$SINGLE" 2>/dev/null | grep -q "$HOST_ARCH"; then
        echo "==> note: single-arch ($HOST_ARCH) build; universal needs a toolchain that honours --triple"
        cp "$SINGLE" "$BIN_OUT"
    else
        echo "==> note: artifact arch != host arch, rebuilding for $HOST_ARCH"
        swift build -c release
        cp "$(find_release_binary "$HOST_ARCH-apple-macosx")" "$BIN_OUT"
    fi
fi

echo "==> binary: $(lipo -info "$BIN_OUT")"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# 动态同步 Info.plist 中的版本号
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true

# 签名走共享逻辑（与 build.sh 同一处，避免两边各写一遍而漂移）
sh "$(dirname "$0")/sign.sh" "$APP"

echo "==> designated requirement: $(codesign -d --requirements - "$APP" 2>&1 | sed -n 's/.*designated => //p' | cut -c1-60)..."

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
