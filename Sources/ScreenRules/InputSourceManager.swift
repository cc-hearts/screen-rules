import Carbon.HIToolbox

struct InputSourceInfo {
    let id: String
    let name: String
}

/// 封装 Text Input Source Services：枚举已启用的输入源、按 ID 切换
enum InputSourceManager {
    private static func tisString(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func allSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list
    }

    /// 已启用且可直接选择的输入源（排除 SCIM 这类“模式容器”）。
    ///
    /// 判据是 `kTISPropertyInputSourceIsSelectCapable`——「能不能直接选中」的权威答案。
    /// 不能按 type 排除 `kTISTypeKeyboardInputMode`：第三方输入法（搜狗、豆包、
    /// 微信输入法）的拼音模式正是这个 type 且 IsSelectCapable=true，是用户真正要选的；
    /// 同名的容器项才是 selectCapable=false 的空壳。按 type 猜会把用户要的那个滤掉。
    static func enabledSources() -> [InputSourceInfo] {
        InputSourceFilter.selectable(allSources().compactMap(facts(for:)))
            .map { InputSourceInfo(id: $0.id, name: $0.name) }
    }

    /// 读一个 TISInputSource 的属性。布尔属性读不到时按 false——
    /// 没有证据表明它可选中，就不能让它出现在菜单里。
    private static func facts(for src: TISInputSource) -> InputSource? {
        func bool(_ key: CFString) -> Bool? {
            guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
            let v = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.boolValue }
            return nil
        }
        return InputSource.make(
            id: tisString(src, kTISPropertyInputSourceID),
            name: tisString(src, kTISPropertyLocalizedName),
            type: tisString(src, kTISPropertyInputSourceType),
            isSelectCapable: bool(kTISPropertyInputSourceIsSelectCapable),
            isEnabled: bool(kTISPropertyInputSourceIsEnabled)
        )
    }

    static func name(for id: String) -> String? {
        enabledSources().first { $0.id == id }?.name
    }

    static func currentID() -> String? {
        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return tisString(cur, kTISPropertyInputSourceID)
    }

    /// 按 ID 切换，并把失败原因说清楚：源不存在、列表为空、
    /// 还是源在但 TIS 拒绝切换（OSStatus 非 0）。
    @discardableResult
    static func select(id: String) -> InputSourceOutcome {
        let available = enabledSources()
        guard !available.isEmpty else {
            return .failed(InputSourceFailure.message(id: id, available: [], osStatus: nil))
        }
        guard let src = allSources().first(where: { tisString($0, kTISPropertyInputSourceID) == id }) else {
            return .failed(InputSourceFailure.message(id: id, available: available, osStatus: nil))
        }
        let status = TISSelectInputSource(src)
        guard status == noErr else {
            return .failed(InputSourceFailure.message(id: id, available: available, osStatus: status))
        }
        return .selected
    }
}

enum InputSourceOutcome: Equatable {
    case selected
    case failed(String)
}

/// 输入源切换失败的日志文案。三种失败要分开说，否则用户会往错的方向排查。
enum InputSourceFailure {
    static func message(id: String, available: [InputSourceInfo], osStatus: OSStatus?) -> String {
        if available.isEmpty {
            return "\(id): 系统里没有任何可选输入源（TIS 列不出来），无法切换"
        }
        guard osStatus == nil else {
            return "\(id): 切换失败 OSStatus \(osStatus!)（该输入源存在但系统拒绝切换）"
        }
        let list = available.map { $0.name + " (" + $0.id + ")" }.joined(separator: ", ")
        return "\(id): 不存在，可选的有：\(list)"
    }
}
