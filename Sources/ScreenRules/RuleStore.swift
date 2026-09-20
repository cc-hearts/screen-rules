import Foundation

enum RuleTarget: String, Codable {
    case main, secondary
    var displayName: String { self == .main ? "主屏" : "副屏" }
}

struct Rule: Codable {
    var bundleID: String
    var appName: String
    var target: RuleTarget?   // nil = 屏幕位置跟随系统默认
    var scale: Double?        // nil = 尺寸跟随系统默认；0.8 表示窗口占目标屏可见区域的 80%
    var inputSourceID: String?  // nil = 输入法跟随系统；否则切到该 App 时自动切换

    /// 菜单里展示用，如「副屏 · 80%」；两项都未设置时返回 nil（规则应被删除）
    var summary: String? {
        switch (target, scale) {
        case let (t?, s?): return "\(t.displayName) · \(Int(s * 100))%"
        case let (t?, nil): return t.displayName
        case let (nil, s?): return "\(Int(s * 100))%"
        case (nil, nil):    return nil
        }
    }
}

/// 规则持久化: ~/Library/Application Support/ScreenRules/rules.json
final class RuleStore {
    static let shared = RuleStore()
    private(set) var rules: [String: Rule] = [:]   // bundleID -> rule

    var configFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenRules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rules.json")
    }

    private init() { load() }

    func rule(for bundleID: String) -> Rule? { rules[bundleID] }

    var sortedRules: [Rule] { rules.values.sorted { $0.appName < $1.appName } }

    func setTarget(bundleID: String, appName: String, target: RuleTarget?) {
        var rule = rules[bundleID] ?? Rule(bundleID: bundleID, appName: appName, target: nil, scale: nil, inputSourceID: nil)
        rule.appName = appName
        rule.target = target
        store(rule)
    }

    func setScale(bundleID: String, appName: String, scale: Double?) {
        var rule = rules[bundleID] ?? Rule(bundleID: bundleID, appName: appName, target: nil, scale: nil, inputSourceID: nil)
        rule.appName = appName
        rule.scale = scale
        store(rule)
    }

    func setInputSource(bundleID: String, appName: String, inputSourceID: String?) {
        var rule = rules[bundleID] ?? Rule(bundleID: bundleID, appName: appName, target: nil, scale: nil, inputSourceID: nil)
        rule.appName = appName
        rule.inputSourceID = inputSourceID
        store(rule)
    }

    /// 三项都为空时删除整条规则
    private func store(_ rule: Rule) {
        if rule.target == nil && rule.scale == nil && rule.inputSourceID == nil {
            rules.removeValue(forKey: rule.bundleID)
        } else {
            rules[rule.bundleID] = rule
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: configFileURL),
              let list = try? JSONDecoder().decode([Rule].self, from: data) else { return }
        rules = Dictionary(list.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sortedRules) else { return }
        try? data.write(to: configFileURL, options: .atomic)
    }
}
