import XCTest
@testable import ScreenRules

/// TIS 读取侧到 InputSource 的转换：属性缺失时怎么定值。
/// 这些决定会直接影响菜单内容和规则能否配成。
final class InputSourceFactsTests: XCTestCase {

    func testBuildsSourceFromAllProperties() {
        let s = InputSource.make(id: "com.bytedance.inputmethod.doubaoime.pinyin",
                                 name: "豆包输入法",
                                 type: "TISTypeKeyboardInputMode",
                                 isSelectCapable: true,
                                 isEnabled: true)
        XCTAssertEqual(s?.id, "com.bytedance.inputmethod.doubaoime.pinyin")
        XCTAssertEqual(s?.name, "豆包输入法")
        XCTAssertEqual(s?.isSelectCapable, true)
        XCTAssertEqual(s?.isEnabled, true)
    }

    func testDropsSourceWithoutID() {
        // 破坏点：id 缺失时造一个占位源。规则是按 ID 匹配的，
        // 没有 ID 的源进了菜单只会让用户配出一条永远匹配不上的规则。
        XCTAssertNil(InputSource.make(id: nil, name: "豆包输入法",
                                 type: "TISTypeKeyboardInputMode",
                                 isSelectCapable: true, isEnabled: true))
    }

    func testDropsSourceWithoutName() {
        // 破坏点：name 缺失时用 ID 顶上。菜单要显示给人看，
        // 显示一长串 bundle ID 等于没有可用信息。
        XCTAssertNil(InputSource.make(id: "com.apple.keylayout.ABC", name: nil,
                                 type: "TISTypeKeyboardLayout",
                                 isSelectCapable: true, isEnabled: true))
    }

    func testDropsSourceWithoutType() {
        // 破坏点：type 缺失时填空串。type 现在是纯记录字段，
        // 但缺失说明这个源不是正常的键盘输入源。
        XCTAssertNil(InputSource.make(id: "com.apple.keylayout.ABC", name: "ABC",
                                 type: nil,
                                 isSelectCapable: true, isEnabled: true))
    }

    func testMissingSelectCapableMeansNotSelectable() {
        // 破坏点：属性读不到时默认 true。读不到恰恰说明没有证据它能被选中，
        // 默认放进菜单会让用户配出一条必然失败的规则（就是这次修的 bug）。
        let s = InputSource.make(id: "com.apple.keylayout.ABC", name: "ABC",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: nil, isEnabled: true)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.isSelectCapable, false)
    }

    func testMissingEnabledMeansNotEnabled() {
        // 破坏点：属性读不到时默认 true。系统设置里关掉的输入源
        // 选不动，列在菜单里等于给用户埋雷。
        let s = InputSource.make(id: "com.apple.keylayout.ABC", name: "ABC",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: true, isEnabled: nil)
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.isEnabled, false)
    }
}
