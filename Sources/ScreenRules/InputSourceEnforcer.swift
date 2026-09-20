import Cocoa

/// 激活 App 时，若规则里配了默认输入法则自动切换（TIS 切换不需要辅助功能权限）
final class InputSourceEnforcer {
    static let shared = InputSourceEnforcer()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        SRLog.log("input-source enforcer started")
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              let id = RuleStore.shared.rule(for: bundleID)?.inputSourceID else { return }
        guard InputSourceManager.currentID() != id else { return }
        let ok = InputSourceManager.select(id: id)
        let name = InputSourceManager.name(for: id) ?? id
        SRLog.log("input-source: \(app.localizedName ?? bundleID) -> \(name) \(ok ? "ok" : "FAILED (source missing?)")")
    }
}
