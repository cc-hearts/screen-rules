#!/bin/sh
# 从 docs/logo-original.jpg 重新生成所有图标资产
#   - docs/app-icon.png              macOS 标准圆角矩形高清图标 (1024x1024)
#   - docs/logo.png / logo-dark.png  README 展示图
#   - Resources/AppIcon.icns         macOS App 图标
set -e
cd "$(dirname "$0")/.."

swift - <<'SWIFT'
import AppKit

let originalPath = "docs/logo-original.jpg"
guard let srcImage = NSImage(contentsOfFile: originalPath) else {
    print("错误: 找不到 \(originalPath)")
    exit(1)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let iconImage = NSImage(size: canvasSize)
iconImage.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// macOS Big Sur / Sonoma / Sequoia 规范尺寸：824x824 居中 (x: 100, y: 100)
let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: iconRect, xRadius: 185, yRadius: 185)

// 外阴影 (柔和自然)
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 32
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowColor = NSColor(white: 0.0, alpha: 0.35)
shadow.set()
NSColor.black.setFill()
path.fill()
ctx.restoreGState()

// 裁剪为标准圆角矩形并绘制 Logo
ctx.saveGState()
path.addClip()
srcImage.draw(in: iconRect, from: NSRect(origin: .zero, size: srcImage.size), operation: .sourceOver, fraction: 1.0)

// 边缘高光线 (提升原生质感)
let strokeColor = NSColor(white: 1.0, alpha: 0.12)
strokeColor.setStroke()
path.lineWidth = 2.0
path.stroke()
ctx.restoreGState()

iconImage.unlockFocus()

guard let tiff = iconImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    print("错误: 无法生成 PNG 数据")
    exit(1)
}

let appIconPng = "docs/app-icon.png"
try! pngData.write(to: URL(fileURLWithPath: appIconPng))
try! pngData.write(to: URL(fileURLWithPath: "docs/logo.png"))
try! pngData.write(to: URL(fileURLWithPath: "docs/logo-dark.png"))
print("==> 已生成 docs/app-icon.png, docs/logo.png, docs/logo-dark.png")

// 生成全套 iconset 分辨率
let iconsetDir = "/tmp/ScreenRules.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let dest = "\(iconsetDir)/\(name)"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    p.arguments = ["-z", "\(size)", "\(size)", appIconPng, "--out", dest]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("==> 已生成 Resources/AppIcon.icns")
} else {
    print("错误: iconutil 执行失败")
    exit(1)
}
SWIFT
