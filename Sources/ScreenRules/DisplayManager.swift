import Cocoa

struct DisplayInfo {
    let id: CGDirectDisplayID
    let frame: CGRect          // AppKit 全局坐标（主屏左下角为原点）
    let visibleFrame: CGRect
    let isMain: Bool
    let name: String
}

enum DisplayManager {
    static func all() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return DisplayInfo(
                id: num?.uint32Value ?? 0,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: screen == NSScreen.screens.first,
                name: screen.localizedName
            )
        }
    }

    static func resolve(_ target: RuleTarget) -> DisplayInfo? {
        let all = all()
        switch target {
        case .main:      return all.first { $0.isMain } ?? all.first
        case .secondary: return all.first { !$0.isMain }   // 单屏时为 nil，跳过
        }
    }

    static func display(containingCocoaPoint point: CGPoint) -> DisplayInfo? {
        all().first { $0.frame.contains(point) } ?? all().first { $0.isMain }
    }

    /// AX 坐标（左上角原点）-> AppKit 坐标（左下角原点），以主屏高度为翻转基准
    static func axToCocoa(_ rect: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoaToAX(_ rect: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
    }
}
