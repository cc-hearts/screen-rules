#!/bin/sh
# 统一的签名逻辑。build.sh（本地开发）和 scripts/package.sh（CI 发版）都走这里。
#
# TCC 的授权（辅助功能、屏幕录制、文件访问）绑定的是 designated requirement。
# 自签名证书的 DR 落在二进制的 cdhash 上，每次重新编译产物内容一变，macOS
# 就认成新程序，已授予的权限全部失效——这就是「每次装完都要重新授权一次」。
# CA 签发的证书（Apple Development）的 DR 是「证书本身」，二进制变了授权仍在。
#
# 所以优先级固定为：Apple Development -> ScreenRules Dev -> ad-hoc。
# 曾经两处脚本各写一遍，package.sh 先换成了 Apple Development，build.sh 还留在
# 自签名，于是本地每次重建都会掉授权。抽成一处，避免再次漂移。
set -e

APP="$1"
if [ -z "$APP" ]; then
    echo "usage: sign.sh <app-bundle>" >&2
    exit 1
fi

sign_with() {
    codesign --force --deep --sign "$1" --identifier com.carl.screenrules "$APP" 2>/dev/null
}

signed_ok() {
    codesign --verify --deep "$APP" 2>/dev/null
}

# 1. Apple Development：DR 是证书本身，重编译不丢授权
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)"
    if [ -n "$IDENTITY" ] && sign_with "$IDENTITY" && signed_ok; then
        echo "==> signed with: $IDENTITY (TCC grants survive rebuilds)"
        exit 0
    fi
    echo "==> Apple Development signing failed, falling back" >&2
fi

# 2. 自签名证书：本机固定证书，但 DR 随二进制内容变，授权会失效
if security find-identity -v -p codesigning 2>/dev/null | grep -q "ScreenRules Dev"; then
    if sign_with "ScreenRules Dev" && signed_ok; then
        echo "==> signed with: ScreenRules Dev (self-signed; expect to re-grant accessibility)"
        exit 0
    fi
    echo "==> ScreenRules Dev signing failed, falling back" >&2
fi

# 3. ad-hoc：没有可用证书时的兜底
codesign --force --deep --sign - --identifier com.carl.screenrules "$APP" 2>/dev/null || true
echo "==> signed ad-hoc (expect to re-grant accessibility)"
