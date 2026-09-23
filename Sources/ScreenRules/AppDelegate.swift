import Cocoa
import ApplicationServices

/// representedObject 载体：一次规则编辑操作（改屏幕 / 改尺寸 / 改输入法）
private final class RuleEdit: NSObject {
    enum Change {
        case target(RuleTarget?)      // nil = 屏幕跟随系统默认
        case scale(Double?)           // nil = 尺寸跟随系统默认
        case inputSource(String?)     // nil = 输入法跟随系统
        case remove                   // 删除整条规则
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
            InputSourceEnforcer.shared.start()
        } else {
            promptForPermission()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
                if self.axTrusted() {
                    timer.invalidate()
                    SRLog.log("permission granted at runtime, starting watcher")
                    WindowMover.shared.start()
                    InputSourceEnforcer.shared.start()
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
            let summary = ruleSummary(rule)
            let item = NSMenuItem(title: "当前 App：\(name)\(summary.isEmpty ? "" : "（\(summary)）")",
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
                let item = NSMenuItem(title: "\(rule.appName) → \(ruleSummary(rule))",
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

        addItem(to: menu, title: "关于 ScreenRules…", action: #selector(openAbout))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ScreenRules", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// 规则摘要：「副屏 · 90% · ABC」
    private func ruleSummary(_ rule: Rule?) -> String {
        guard let rule else { return "" }
        var parts: [String] = []
        if let s = rule.summary { parts.append(s) }
        if let id = rule.inputSourceID { parts.append(InputSourceManager.name(for: id) ?? id) }
        return parts.joined(separator: " · ")
    }

    /// 单个 App 的规则编辑子菜单：屏幕 + 尺寸 + 输入法 + 删除
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

        sub.addItem(.separator())
        let imeHeader = NSMenuItem(title: "输入法（切到此 App 时生效）", action: nil, keyEquivalent: "")
        imeHeader.isEnabled = false
        sub.addItem(imeHeader)
        let imeDefault = addItem(to: sub, title: "系统默认", action: #selector(setRule(_:)))
        imeDefault.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .inputSource(nil))
        imeDefault.state = rule?.inputSourceID == nil ? .on : .off
        imeDefault.indentationLevel = 1
        for src in InputSourceManager.enabledSources() {
            let item = addItem(to: sub, title: src.name, action: #selector(setRule(_:)))
            item.representedObject = RuleEdit(bundleID: bundleID, appName: appName, change: .inputSource(src.id))
            item.state = rule?.inputSourceID == src.id ? .on : .off
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
            WindowMover.shared.moveExistingWindows(bundleID: edit.bundleID)
        case .scale(let scale):
            SRLog.log("rule set: \(edit.appName) (\(edit.bundleID)) scale -> \(scale.map { "\(Int($0 * 100))%" } ?? "默认")")
            store.setScale(bundleID: edit.bundleID, appName: edit.appName, scale: scale)
            WindowMover.shared.moveExistingWindows(bundleID: edit.bundleID)
        case .inputSource(let id):
            SRLog.log("rule set: \(edit.appName) (\(edit.bundleID)) ime -> \(id ?? "默认")")
            store.setInputSource(bundleID: edit.bundleID, appName: edit.appName, inputSourceID: id)
            // 设置的就是当前前台 App：立即切换
            if let id, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == edit.bundleID {
                InputSourceManager.select(id: id)
            }
        case .remove:
            SRLog.log("rule removed: \(edit.appName) (\(edit.bundleID))")
            store.setTarget(bundleID: edit.bundleID, appName: edit.appName, target: nil)
            store.setScale(bundleID: edit.bundleID, appName: edit.appName, scale: nil)
            store.setInputSource(bundleID: edit.bundleID, appName: edit.appName, inputSourceID: nil)
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

    @objc private func openAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [
                NSApplication.AboutPanelOptionKey.applicationName: "ScreenRules"
            ]
        )
    }
}
