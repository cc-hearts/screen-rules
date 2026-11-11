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

# 签名
#
# TCC 的授权（辅助功能、屏幕录制、文件访问）绑定的是 designated requirement。
# 自签名证书的 DR 落在二进制的 cdhash 上，每次重新编译产物内容一变，
# macOS 就认成新程序，已授予的权限全部失效——这就是「每次装完都要重新授权」。
# CA 签发的证书（Apple Development）的 DR 是「证书本身」，二进制变了授权仍在。
# 所以优先用 Apple Development 签名，只在找不到时才退回自签名。
SIGN_IDENTITY=""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" --identifier com.carl.screenrules "$APP" 2>/dev/null \
        && echo "==> signed with: $SIGN_IDENTITY (TCC grants survive rebuilds)" \
        || echo "==> Apple Development signing failed, falling back"
fi

if ! codesign --verify --deep "$APP" 2>/dev/null; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "ScreenRules Dev"; then
        codesign --force --deep --sign "ScreenRules Dev" --identifier com.carl.screenrules "$APP" 2>/dev/null || true
        echo "==> signed with: ScreenRules Dev (self-signed; expect to re-grant accessibility)"
    else
        codesign --force --deep --sign - --identifier com.carl.screenrules "$APP" 2>/dev/null || true
        echo "==> signed ad-hoc (expect to re-grant accessibility)"
    fi
fi

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
