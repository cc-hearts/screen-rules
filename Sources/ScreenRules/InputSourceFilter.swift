import Foundation

/// 一个输入源在 TIS 侧读到的、过滤所需的事实集合。
struct InputSource: Equatable {
    let id: String
    let name: String
    let type: String
    let isSelectCapable: Bool
    let isEnabled: Bool

    /// 从 TIS 读到的原始属性构造。id / name / type 缺一个就认为这个源
    /// 不可用（返回 nil）：规则按 ID 匹配，菜单要显示给人看。
    /// 布尔属性读不到时一律按 false——没有证据表明它能被选中，就不能放进菜单。
    static func make(id: String?, name: String?, type: String?,
                     isSelectCapable: Bool?, isEnabled: Bool?) -> InputSource? {
        guard let id, let name, let type else { return nil }
        return InputSource(id: id, name: name, type: type,
                           isSelectCapable: isSelectCapable ?? false,
                           isEnabled: isEnabled ?? false)
    }
}

/// 决定哪些输入源该出现在菜单里、能被选进规则。
///
/// 判据是 `kTISPropertyInputSourceIsSelectCapable`——「能不能直接选中」的权威答案。
/// 不能按 type 过滤：第三方输入法（搜狗、豆包、微信输入法）的拼音模式
/// type 正是 `TISTypeKeyboardInputMode`，而它是用户真正要选的那个；
/// 同名的容器项才是 `selectCapable == false` 的空壳。
enum InputSourceFilter {
    static func selectable(_ sources: [InputSource]) -> [InputSource] {
        var seen = Set<String>()
        var out: [InputSource] = []
        for src in sources where src.isSelectCapable && src.isEnabled {
            guard !seen.contains(src.id) else { continue }
            seen.insert(src.id)
            out.append(src)
        }
        return out
    }
}
