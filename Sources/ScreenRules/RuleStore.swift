import Foundation

enum RuleTarget: String, Codable {
    case main, secondary
    var displayName: String { self == .main ? "主屏" : "副屏" }
}

struct Rule: Codable {
    var bundleID: String
    var appName: String
    var target: RuleTarget
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

    /// target 为 nil 表示删除规则（跟随系统默认）
    func set(bundleID: String, appName: String, target: RuleTarget?) {
        if let target {
            rules[bundleID] = Rule(bundleID: bundleID, appName: appName, target: target)
        } else {
            rules.removeValue(forKey: bundleID)
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
