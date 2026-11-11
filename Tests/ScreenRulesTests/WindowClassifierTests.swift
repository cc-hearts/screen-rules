import XCTest
@testable import ScreenRules

/// 窗口判定测试：只搬「主窗口」，弹窗/看图窗口/面板一律跳过。
/// 每个用例都对应一条会被改坏的生产逻辑。
final class WindowClassifierTests: XCTestCase {

    // MARK: - 该管的：App 的顶级、可调尺寸的标准主窗口

    func testManagesResizableTopLevelStandardWindow() {
        // 破坏点：删掉「可调尺寸」或「顶级」任一律，正常主窗口会被漏掉
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .manage)
    }

    func testManagesWindowWhenMainFlagUnknown() {
        // 破坏点：把 isMain == nil 当成「非主窗口」跳过，不报 AXMain 的 App 主窗口会全部失效
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .manage)
    }

    func testManagesSecondWindowOfMultiWindowApp() {
        // 破坏点：改成「每个 App 只归位第一个窗口」，Chrome/Zed 多窗口会被漏掉
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: true,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .manage)
    }

    // MARK: - 该跳过的

    func testSkipsWindowAttachedToAnotherWindow() {
        // 破坏点：删掉「父元素必须是 App」这一条，挂在别的窗口下的 sheet/对话框会被当主窗口搬走
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: false,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.attachedToWindow))
    }

    func testSkipsNonResizablePanel() {
        // 破坏点：删掉「必须可调尺寸」，固定尺寸的 HUD/attach 面板会被搬走
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: false,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.notResizable))
    }

    func testSkipsFloatingWindow() {
        // 破坏点：删掉「layer 必须为 0」，浮动面板/通知/候选框会被搬走
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 21,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.floating))
    }

    func testSkipsMinimizedWindow() {
        // 破坏点：删掉「已最小化不处理」，收回 Dock 的窗口会被强行拉出来归位
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: true)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.minimized))
    }

    func testSkipsNonStandardSubrole() {
        // 破坏点：放宽 subrole 白名单，系统对话框/抽屉会被搬走
        let facts = WindowFacts(subrole: "AXDialog",
                                isMain: nil,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.notStandardWindow))
    }

    func testSkipsWindowDeclaringItIsNotMain() {
        // 破坏点：删掉「AXMain 为 false 就跳过」，看图窗口/临时弹窗会被当主窗口搬走
        let facts = WindowFacts(subrole: "AXStandardWindow",
                                isMain: false,
                                parentIsApp: true,
                                isResizable: true,
                                cgLayer: 0,
                                isMinimized: false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.notMainWindow))
    }
}
