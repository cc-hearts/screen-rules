import Cocoa
import ApplicationServices

/// representedObject 载体：一次规则编辑操作（改屏幕 或 改尺寸）
private final class RuleEdit: NSObject {
    enum Change {
        case target(RuleTarget?)   // nil = 屏幕跟随系统默认
        case scale(Double?)        // nil = 尺寸跟随系统默认
        case remove                // 删除整条规则
    }
    let bundleID: String
    let appName: String
    let change: Change
    init(bundleID: String, appName: String, change: Change) {
        self.bundleID = bundleID
        self.appName = appName
        self.change = change
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    private static let scaleChoices: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    func applicationDidFinishLaunching(_ notification: Notification) {
        SRLog.truncateIfNeeded()
        SRLog.log("launched, axTrusted=\(axTrusted())")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "display.2", accessibilityDescription: "ScreenRules") {
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "SR"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if axTrusted() {
            WindowMover.shared.start()
        } else {
            promptForPermission()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
                if self.axTrusted() {
                    timer.invalidate()
                    SRLog.log("permission granted at runtime, starting watcher")
                    WindowMover.shared.start()
                }
            }
        }
    }

    // MARK: - 辅助功能权限

    private func axTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    private func promptForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - 菜单（每次打开时重建）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !axTrusted() {
            addItem(to: menu, title: "⚠️ 需要辅助功能权限 — 点击去授权", action: #selector(openAccessibilitySettings))
            menu.addItem(.separator())
        }

        // 当前活跃 App：快捷设置
        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let name = front.localizedName ?? bundleID
            let rule = RuleStore.shared.rule(for: bundleID)
            let item = NSMenuItem(title: "当前 App：\(name)\(rule?.summary.map { "（\($0)）" } ?? "")",
                                  action: nil, keyEquivalent: "")
            item.submenu = ruleMenu(bundleID: bundleID, appName: name, rule: rule)
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // 已有规则
        let rules = RuleStore.shared.sortedRules
        if !rules.isEmpty {
            let header = NSMenuItem(title: "规则", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for rule in rules {
                let item = NSMenuItem(title: "\(rule.appName) → \(rule.summary ?? "")",
                                      action: nil, keyEquivalent: "")
                item.submenu = ruleMenu(bundleID: rule.bundleID, appName: rule.appName, rule: rule)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        addItem(to: menu, title: "立即按规则整理所有窗口", action: #selector(applyAll))
        addItem(to: menu, title: "打开规则文件…", action: #selector(revealConfig))
        addItem(to: menu, title: "打开调试日志…", action: #selector(openLog))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ScreenRules", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// 单个 App 的规则编辑子菜单：屏幕 + 尺寸 + 删除
    private func ruleMenu(bundleID: String, appName: String, rule: Rule?) -> NSMenu {
        let sub = NSMenu()

        let screenHeader = NSMenuItem(title: "屏幕", action: nil, keyEquivalent: "")
        screenHeader.isEnabled = false
        sub.addItem(screenHeader)
        let screenChoices: [(String, RuleTarget?)] = [("系统默认", nil), ("主屏", .main), ("副屏", .secondary)]
        for (title, target) in screenChoices {
            let item = addItem(to: sub, title: title, action: #selector(setRule(_:)))
            item.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .target(target))
            item.state = target == rule?.target ? .on : .off
            item.indentationLevel = 1
        }

        sub.addItem(.separator())
        let sizeHeader = NSMenuItem(title: "窗口大小（占屏幕比例）", action: nil, keyEquivalent: "")
        sizeHeader.isEnabled = false
        sub.addItem(sizeHeader)
        let defaultItem = addItem(to: sub, title: "系统默认", action: #selector(setRule(_:)))
        defaultItem.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .scale(nil))
        defaultItem.state = rule?.scale == nil ? .on : .off
        defaultItem.indentationLevel = 1
        for scale in Self.scaleChoices {
            let item = addItem(to: sub, title: "\(Int(scale * 100))%", action: #selector(setRule(_:)))
            item.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .scale(scale))
            item.state = rule?.scale.map { abs($0 - scale) < 0.001 } ?? false ? .on : .off
            item.indentationLevel = 1
        }

        if rule != nil {
            sub.addItem(.separator())
            let del = addItem(to: sub, title: "删除规则", action: #selector(setRule(_:)))
            del.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .remove)
        }
        return sub
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    // MARK: - 动作

    @objc private func setRule(_ sender: NSMenuItem) {
        guard let edit = sender.representedObject as? RuleEdit else { return }
        let store = RuleStore.shared
        switch edit.change {
        case .target(let target):
            SRLog.log("rule set: \(edit.appName) (\(edit.bundleID)) screen -> \(target?.displayName ?? "默认")")
            store.setTarget(bundleID: edit.bundleID, appName: edit.appName, target: target)
        case .scale(let scale):
            SRLog.log("rule set: \(edit.appName) (\(edit.bundleID)) scale -> \(scale.map { "\(Int($0 * 100))%" } ?? "默认")")
            store.setScale(bundleID: edit.bundleID, appName: edit.appName, scale: scale)
        case .remove:
            SRLog.log("rule removed: \(edit.appName) (\(edit.bundleID))")
            store.setTarget(bundleID: edit.bundleID, appName: edit.appName, target: nil)
            store.setScale(bundleID: edit.bundleID, appName: edit.appName, scale: nil)
        }
        // 设置规则后，把这个 App 已打开的窗口也立即归位
        if store.rule(for: edit.bundleID) != nil {
            WindowMover.shared.moveExistingWindows(bundleID: edit.bundleID)
        }
    }

    @objc private func applyAll() {
        WindowMover.shared.applyToAllExistingWindows()
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([RuleStore.shared.configFileURL])
    }

    @objc private func openLog() {
        NSWorkspace.shared.open([SRLog.url],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        promptForPermission()
    }
}
