import AppKit

// 用法: swift scripts/make_icon.swift <输出png路径>
// 1024x1024 透明底线条图标: 双显示器 + 窗口搬家箭头，蓝紫渐变描边
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/logo.png"
let W = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rounded(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// 主线条：两台显示器 + 支架 + 箭头
let main = CGMutablePath()
let lf = CGRect(x: 70, y: 400, width: 380, height: 260)    // 左：主屏
main.addPath(rounded(lf, 36))
main.move(to: CGPoint(x: lf.midX, y: lf.minY))
main.addLine(to: CGPoint(x: lf.midX, y: lf.minY - 60))
main.move(to: CGPoint(x: lf.midX - 90, y: lf.minY - 60))
main.addLine(to: CGPoint(x: lf.midX + 90, y: lf.minY - 60))

let rf = CGRect(x: 574, y: 400, width: 380, height: 260)   // 右：副屏
main.addPath(rounded(rf, 36))
main.move(to: CGPoint(x: rf.midX, y: rf.minY))
main.addLine(to: CGPoint(x: rf.midX, y: rf.minY - 60))
main.move(to: CGPoint(x: rf.midX - 90, y: rf.minY - 60))
main.addLine(to: CGPoint(x: rf.midX + 90, y: rf.minY - 60))

let ay: CGFloat = 530                                       // 箭头：窗口搬家
main.move(to: CGPoint(x: 472, y: ay))
main.addLine(to: CGPoint(x: 552, y: ay))
main.move(to: CGPoint(x: 520, y: ay + 32))
main.addLine(to: CGPoint(x: 554, y: ay))
main.addLine(to: CGPoint(x: 520, y: ay - 32))

// 副屏里的窗口（细一点的线，区分层次）
let win = CGMutablePath()
win.addPath(rounded(rf.insetBy(dx: 42, dy: 42), 18))

// 描边转区域，作为渐变的裁剪蒙版
ctx.addPath(main.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.addPath(win.copy(strokingWithWidth: 20, lineCap: .round, lineJoin: .round, miterLimit: 10))
ctx.clip()

// 左上(蓝) -> 右下(紫) 渐变
let grad = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(srgbRed: 0.23, green: 0.51, blue: 0.98, alpha: 1),
    CGColor(srgbRed: 0.49, green: 0.34, blue: 0.93, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("written: \(outPath)")
