import XCTest
@testable import ScreenRules

/// 输入源过滤测试：菜单里该出现「能直接选中」的输入源。
/// 每个用例对应一条会被改坏的生产逻辑。
final class InputSourceFilterTests: XCTestCase {

    // MARK: - 该出现的

    func testIncludesSelectableInputMode() {
        // 破坏点：按 type 排除 TISTypeKeyboardInputMode。第三方输入法的拼音模式
        // （如豆包、搜狗）正是这个 type 且 IsSelectCapable=true，是用户真正要选的。
        // 老代码把它排掉了，导致菜单里选不到、只能手改 rules.json。
        let s = InputSource(id: "com.bytedance.inputmethod.doubaoime.pinyin",
                            name: "豆包输入法",
                            type: "TISTypeKeyboardInputMode",
                            isSelectCapable: true,
                            isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([s]), [s])
    }

    func testIncludesKeyboardLayout() {
        // 破坏点：把非 mode 类型也一起排除。ABC 这类键盘布局 type 是
        // TISTypeKeyboardLayout，是合法的可选输入源（Ghostty 的规则就在用它）。
        let s = InputSource(id: "com.apple.keylayout.ABC",
                            name: "ABC",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: true,
                            isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([s]), [s])
    }

    // MARK: - 该排除的

    func testExcludesModeContainer() {
        // 破坏点：改用 type 白名单之外的判断。SCIM / 第三方 IME 的容器项
        // IsSelectCapable=false，选中它毫无效果，出现在菜单里只会误导。
        let s = InputSource(id: "com.bytedance.inputmethod.doubaoime",
                            name: "豆包输入法",
                            type: "TISTypeKeyboardInputMethodEnabled",
                            isSelectCapable: false,
                            isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([s]), [])
    }

    func testExcludesDisabledSource() {
        // 破坏点：去掉 enabled 检查。系统设置里关掉的输入源选不动，
        // 列在菜单里会让用户配出一个必然失败的规则。
        let s = InputSource(id: "com.apple.keylayout.US",
                            name: "US",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: true,
                            isEnabled: false)
        XCTAssertEqual(InputSourceFilter.selectable([s]), [])
    }

    func testDeduplicatesByID() {
        // 破坏点：去掉按 ID 去重。TIS 列表里同一个输入源可能出现多次
        // （如按类别重复列出），菜单里会出现重复项。
        let a = InputSource(id: "com.apple.keylayout.ABC", name: "ABC",
                            type: "TISTypeKeyboardLayout", isSelectCapable: true, isEnabled: true)
        let b = InputSource(id: "com.apple.keylayout.ABC", name: "ABC",
                            type: "TISTypeKeyboardLayout", isSelectCapable: true, isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([a, b]), [a])
    }

    func testKeepsBothWhenContainerAndModeShareAName() {
        // 破坏点：按名字去重而不是按 ID。容器项和它下的拼音模式同名
        // （都叫「豆包输入法」），按名字去重会把能选的那个误删。
        let container = InputSource(id: "com.bytedance.inputmethod.doubaoime",
                                    name: "豆包输入法",
                                    type: "TISTypeKeyboardInputMethodEnabled",
                                    isSelectCapable: false, isEnabled: true)
        let mode = InputSource(id: "com.bytedance.inputmethod.doubaoime.pinyin",
                               name: "豆包输入法",
                               type: "TISTypeKeyboardInputMode",
                               isSelectCapable: true, isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([container, mode]), [mode])
    }

    func testIncludesSelectableSourceOfAnyOtherType() {
        // 破坏点：加一道 type 白名单（只放 KeyboardLayout / KeyboardInputMode）。
        // 这次 bug 的根源就是按 type 猜「哪些算输入源」：手写输入法的
        // TISTypeHandwritingInputMode 同样是 selectCapable=true，被白名单挡掉。
        // 判据只能是 selectCapable，type 不参与判断。
        let s = InputSource(id: "com.apple.inputmethod.SCIM.handwriting",
                            name: "手写输入",
                            type: "TISTypeHandwritingInputMode",
                            isSelectCapable: true,
                            isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([s]), [s])
    }

    func testKeepsDistinctSourcesThatShareADisplayName() {
        // 破坏点：把去重键从 ID 换成 name。两个不同的可选项可以显示同一个名字
        // （例如 ABC 与 ABC - Extended、或两个第三方输入法都叫「拼音」），
        // 按名字去重会让用户少一个能选且真正存在的输入源。
        let a = InputSource(id: "com.apple.keylayout.ABC",
                            name: "ABC",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: true, isEnabled: true)
        let b = InputSource(id: "com.apple.keylayout.ABCExtended",
                            name: "ABC",
                            type: "TISTypeKeyboardLayout",
                            isSelectCapable: true, isEnabled: true)
        XCTAssertEqual(InputSourceFilter.selectable([a, b]), [a, b])
    }
}
