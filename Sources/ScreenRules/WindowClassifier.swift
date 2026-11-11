import Foundation

/// 一个窗口在 AX / CG 侧读到的、判定所需的事实集合。
/// 只放纯数据，不含任何 AppKit/AX 依赖——这样判定逻辑可以在测试里直接驱动。
struct WindowFacts {
    var subrole: String?          // AXSubrole，如 AXStandardWindow / AXDialog
    var isMain: Bool?             // AXMain；读不到为 nil
    var parentIsApp: Bool         // 父元素角色是否为 AXApplication
    var isResizable: Bool         // 有没有缩放按钮 / 可调尺寸
    var cgLayer: Int              // CGWindowLayer
    var isMinimized: Bool         // AXMinimized
}

enum WindowClass: Equatable {
    case manage
    case skip(SkipReason)
}

enum SkipReason: Equatable {
    case notStandardWindow
    case notMainWindow
    case attachedToWindow
    case notResizable
    case floating
    case minimized

    /// 日志里可读的原因，如 "skipped(not-main-window)"
    var logName: String {
        switch self {
        case .notStandardWindow: return "not-standard-window"
        case .notMainWindow:     return "not-main-window"
        case .attachedToWindow:  return "attached-to-window"
        case .notResizable:      return "not-resizable"
        case .floating:          return "floating"
        case .minimized:         return "minimized"
        }
    }
}

extension SkipReason: CustomStringConvertible {
    var description: String { logName }
}

/// 判定「这个窗口该不该被 ScreenRules 归位」。
///
/// 语义：只管 App 的**主窗口**（会话主窗口、多开窗口、文档窗口）；
/// 看图窗口、对话框、sheet、浮动面板、HUD、候选框一律不碰——
/// 那些由系统或宿主 App 自己定位，我们插手只会添乱。
enum WindowClassifier {
    static func classify(_ facts: WindowFacts) -> WindowClass {
        // 1. 只认标准主窗口。系统自报 AXDialog / AXSheet / AXDrawer 的面板由系统自己定位
        guard facts.subrole == "AXStandardWindow" else { return .skip(.notStandardWindow) }
        // 2. 窗口自己声明「我不是主窗口」时跳过——看图窗口、临时弹窗走这条。
        //    读不到 AXMain（nil）时不拦：有些 App 建窗时还没把 main 立起来，硬卡会漏掉真主窗口
        if facts.isMain == false { return .skip(.notMainWindow) }
        // 3. 挂在别的窗口下的（sheet、attach 对话框）不碰
        guard facts.parentIsApp else { return .skip(.attachedToWindow) }
        // 4. 固定尺寸的面板/HUD 不碰
        guard facts.isResizable else { return .skip(.notResizable) }
        // 5. 浮动层（通知、候选框、浮动面板）不碰
        guard facts.cgLayer == 0 else { return .skip(.floating) }
        // 6. 已收回 Dock 的不碰——别把用户主动收起的窗口强行拉出来
        guard !facts.isMinimized else { return .skip(.minimized) }
        return .manage
    }
}
