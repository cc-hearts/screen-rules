import XCTest
@testable import ScreenRules

/// 输入源切换失败时的日志文案：要说清「哪儿错了」，而不是一句
/// 「FAILED (source missing?)」让用户猜。
final class InputSourceFailureMessageTests: XCTestCase {

    func testSaysSourceDoesNotExistAndListsWhatIsAvailable() {
        // 破坏点：只说 "source missing?"。规则里的 ID 在系统里不存在
        // （用户换了输入法，SCIM 就是这么失效的），日志必须直接给出
        // 系统里实际可选的输入源，用户才知道该改成什么。
        let msg = InputSourceFailure.message(
            id: "com.apple.inputmethod.SCIM",
            available: [InputSourceInfo(id: "com.apple.keylayout.ABC", name: "ABC"),
                        InputSourceInfo(id: "com.bytedance.inputmethod.doubaoime.pinyin", name: "豆包输入法")],
            osStatus: nil)
        XCTAssertTrue(msg.contains("com.apple.inputmethod.SCIM"), msg)
        XCTAssertTrue(msg.contains("不存在"), msg)
        XCTAssertTrue(msg.contains("ABC"), msg)
        XCTAssertTrue(msg.contains("豆包输入法"), msg)
    }

    func testSaysNoInputSourceAvailableAtAll() {
        // 破坏点：列表为空时也照拼「可用：」。一个都没有时问题在别处
        // （TIS 列不出来），文案要区分开，否则用户以为是自己配错了。
        let msg = InputSourceFailure.message(id: "com.apple.keylayout.ABC",
                                            available: [],
                                            osStatus: noErr)
        XCTAssertTrue(msg.contains("没有任何可选输入源"), msg)
    }

    func testDistinguishesSelectionErrorFromMissingSource() {
        // 破坏点：找到输入源但 TISSelectInputSource 失败时也说「不存在」。
        // 这个源明明在可选列表里，切换失败是另一回事（OSStatus 非 0），
        // 说成「不存在」会把用户引向错误的排查方向。
        let msg = InputSourceFailure.message(
            id: "com.bytedance.inputmethod.doubaoime.pinyin",
            available: [InputSourceInfo(id: "com.bytedance.inputmethod.doubaoime.pinyin", name: "豆包输入法")],
            osStatus: -50)
        XCTAssertTrue(msg.contains("切换失败"), msg)
        XCTAssertFalse(msg.contains("不存在"), msg)
        XCTAssertTrue(msg.contains("-50"), msg)
    }
}
