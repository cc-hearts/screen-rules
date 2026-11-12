import XCTest
import ApplicationServices
@testable import ScreenRules

/// AX 读取侧到 WindowFacts 的转换。
///
/// 这些用例盯的是「把 AX 属性原文变成事实」这一步——b2ef5d6 的回归就出在
/// 这里：AXZoomButton / AXGrowArea 的值是 AXUIElementRef，被按 String 读，
/// 于是 isResizable 恒为 false，所有窗口都被判 not-resizable，
/// 全部规则失效。纯判定层的测试覆盖不到这一层，所以当时全绿。
///
/// 用例里用真实的 CF 值（AXUIElementCreateSystemWide() 造出真的 AXUIElementRef、
/// 真的 CFString / CFBoolean），不造假对象——桥接行为正是被测的东西。
final class WindowFactsExtractionTests: XCTestCase {

    /// 破坏点：把「有缩放按钮」当成字符串读。AXZoomButton 的值是
    /// AXUIElementRef，按 String 读恒为 nil → isResizable 恒 false →
    /// 每个正常主窗口都被判 not-resizable，规则一条都不生效。
    func testZoomButtonElementMakesWindowResizable() {
        let zoomButton: CFTypeRef = AXUIElementCreateSystemWide()

        let facts = WindowFacts.make(subrole: kAXStandardWindowSubrole as CFString,
                                     isMain: nil,
                                     parentIsApp: true,
                                     zoomButton: zoomButton,
                                     growArea: nil,
                                     cgLayer: 0,
                                     isMinimized: nil)

        XCTAssertTrue(facts.isResizable)
        XCTAssertEqual(WindowClassifier.classify(facts), .manage)
    }

    /// 破坏点：只认 AXZoomButton 不认 AXGrowArea。只有缩放区的窗口会被误判。
    func testGrowAreaAloneMakesWindowResizable() {
        let growArea: CFTypeRef = AXUIElementCreateSystemWide()

        let facts = WindowFacts.make(subrole: kAXStandardWindowSubrole as CFString,
                                     isMain: nil,
                                     parentIsApp: true,
                                     zoomButton: nil,
                                     growArea: growArea,
                                     cgLayer: 0,
                                     isMinimized: nil)

        XCTAssertTrue(facts.isResizable)
    }

    /// 破坏点：两个元素属性都读不到时当成可调尺寸。固定尺寸的 HUD /
    /// attach 面板会被搬走——这条守卫不能因为修上一个 bug 而被拆掉。
    func testWindowWithNoZoomButtonOrGrowAreaIsNotResizable() {
        let facts = WindowFacts.make(subrole: kAXStandardWindowSubrole as CFString,
                                     isMain: nil,
                                     parentIsApp: true,
                                     zoomButton: nil,
                                     growArea: nil,
                                     cgLayer: 0,
                                     isMinimized: nil)

        XCTAssertFalse(facts.isResizable)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.notResizable))
    }

    /// 破坏点：修 isResizable 时顺手改坏了 subrole / isMain 的读取。
    /// AXSubrole 是 CFString、AXMain 是 CFBoolean，两者的桥接要分开保持。
    func testReadsSubroleStringAndMainBooleanIndependently() {
        let facts = WindowFacts.make(subrole: kAXStandardWindowSubrole as CFString,
                                     isMain: kCFBooleanFalse,
                                     parentIsApp: true,
                                     zoomButton: AXUIElementCreateSystemWide(),
                                     growArea: nil,
                                     cgLayer: 0,
                                     isMinimized: nil)

        XCTAssertEqual(facts.subrole, "AXStandardWindow")
        XCTAssertEqual(facts.isMain, false)
        XCTAssertEqual(WindowClassifier.classify(facts), .skip(.notMainWindow))
    }

    /// 破坏点：属性值类型不对时（读到了别的类型）当成存在。
    /// 元素属性必须是元素，字符串不算「有缩放按钮」。
    func testStringValueDoesNotCountAsZoomButton() {
        let notAnElement: CFTypeRef = "AXStandardWindow" as CFString

        let facts = WindowFacts.make(subrole: kAXStandardWindowSubrole as CFString,
                                     isMain: nil,
                                     parentIsApp: true,
                                     zoomButton: notAnElement,
                                     growArea: nil,
                                     cgLayer: 0,
                                     isMinimized: nil)

        XCTAssertFalse(facts.isResizable)
    }
}
