import AppKit

// 用法: swift scripts/make_icon.swift <输出png路径>
// 生成 1024x1024 图标: 蓝紫渐变圆角底 + 双显示器 + 搬家箭头
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/logo.png"
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

// 背景：macOS 风格圆角方块 + 渐变
let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = NSBezierPath(roundedRect: bg, xRadius: 185, yRadius: 185)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.98, alpha: 1),   // 顶：亮蓝
    NSColor(calibratedRed: 0.44, green: 0.32, blue: 0.93, alpha: 1),   // 底：紫
])!
gradient.draw(in: bgPath, angle: -90)

func drawMonitor(frame: CGRect, color: NSColor, lineWidth: CGFloat, filledWindow: Bool) {
    let screen = NSBezierPath(roundedRect: frame, xRadius: 26, yRadius: 26)
    screen.lineWidth = lineWidth
    color.setStroke()
    screen.stroke()
    // 支架 + 底座
    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: frame.midX, y: frame.minY))
    stand.line(to: NSPoint(x: frame.midX, y: frame.minY - 46))
    stand.move(to: NSPoint(x: frame.midX - 70, y: frame.minY - 46))
    stand.line(to: NSPoint(x: frame.midX + 70, y: frame.minY - 46))
    stand.lineWidth = lineWidth
    stand.lineCapStyle = .round
    color.setStroke()
    stand.stroke()
    if filledWindow {
        let win = NSBezierPath(roundedRect: frame.insetBy(dx: 34, dy: 34), xRadius: 14, yRadius: 14)
        color.setFill()
        win.fill()
    }
}

let lw: CGFloat = 26
// 左：主屏（半透明，空）
drawMonitor(frame: CGRect(x: 170, y: 520, width: 300, height: 210),
            color: NSColor.white.withAlphaComponent(0.45), lineWidth: lw, filledWindow: false)
// 右：副屏（实色，内含窗口）
drawMonitor(frame: CGRect(x: 554, y: 520, width: 300, height: 210),
            color: NSColor.white, lineWidth: lw, filledWindow: true)
// 中间箭头：窗口搬家
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 484, y: 625))
arrow.line(to: NSPoint(x: 540, y: 625))
arrow.move(to: NSPoint(x: 512, y: 655))
arrow.line(to: NSPoint(x: 542, y: 625))
arrow.line(to: NSPoint(x: 512, y: 595))
arrow.lineWidth = 24
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.8).setStroke()
arrow.stroke()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: outPath))
print("written: \(outPath)")
