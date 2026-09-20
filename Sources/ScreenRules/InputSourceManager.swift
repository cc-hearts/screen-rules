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

    /// 已启用且可直接选择的输入源（排除 SCIM 这类“模式容器”）
    static func enabledSources() -> [InputSourceInfo] {
        var seen = Set<String>()
        return allSources().compactMap { src in
            guard let id = tisString(src, kTISPropertyInputSourceID),
                  let name = tisString(src, kTISPropertyLocalizedName),
                  tisString(src, kTISPropertyInputSourceType) != (kTISTypeKeyboardInputMode as String),
                  !seen.contains(id) else { return nil }
            seen.insert(id)
            return InputSourceInfo(id: id, name: name)
        }
    }

    static func name(for id: String) -> String? {
        enabledSources().first { $0.id == id }?.name
    }

    static func currentID() -> String? {
        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return tisString(cur, kTISPropertyInputSourceID)
    }

    @discardableResult
    static func select(id: String) -> Bool {
        guard let src = allSources().first(where: { tisString($0, kTISPropertyInputSourceID) == id }) else { return false }
        return TISSelectInputSource(src) == noErr
    }
}
