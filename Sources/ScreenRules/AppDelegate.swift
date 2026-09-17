import Cocoa
import ApplicationServices

/// representedObject 载体：一次规则编辑操作
private final class RuleEdit: NSObject {
    let bundleID: String
    let appName: String
    let target: RuleTarget?   // nil = 跟随系统默认（删除规则）
    init(bundleID: String, appName: String, target: RuleTarget?) {
        self.bundleID = bundleID
        self.appName = appName
        self.target = target
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "display.2", accessibilityDescription: "ScreenRules") {
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "SR"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if self.axTrusted() {
            WindowMover.shared.start()
        } else {
            promptForPermission()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { timer in
                if self.axTrusted() {
                    timer.invalidate()
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
            let header = NSMenuItem(title: "当前 App：\(name)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let current = RuleStore.shared.rule(for: bundleID)?.target
            let choices: [(String, RuleTarget?)] = [
                ("跟随系统默认", nil),
                ("新窗口打开在主屏", .main),
                ("新窗口打开在副屏", .secondary),
            ]
            for (title, target) in choices {
                let item = addItem(to: menu, title: title, action: #selector(setRule(_:)))
                item.representedObject = RuleEdit(bundleID: bundleID, appName: name, target: target)
                item.state = target == current ? .on : .off
                item.indentationLevel = 1
            }
            menu.addItem(.separator())
        }

        // 已有规则
        let rules = RuleStore.shared.sortedRules
        if !rules.isEmpty {
            let header = NSMenuItem(title: "规则", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for rule in rules {
                let item = NSMenuItem(title: "\(rule.appName) → \(rule.target.displayName)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for target in [RuleTarget.main, .secondary] {
                    let si = addItem(to: sub, title: target.displayName, action: #selector(setRule(_:)))
                    si.representedObject = RuleEdit(bundleID: rule.bundleID, appName: rule.appName, target: target)
                    si.state = target == rule.target ? .on : .off
                }
                sub.addItem(.separator())
                let del = addItem(to: sub, title: "删除规则", action: #selector(setRule(_:)))
                del.representedObject = RuleEdit(bundleID: rule.bundleID, appName: rule.appName, target: nil)
                item.submenu = sub
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        addItem(to: menu, title: "立即按规则整理所有窗口", action: #selector(applyAll))
        addItem(to: menu, title: "打开规则文件…", action: #selector(revealConfig))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 ScreenRules", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
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
        RuleStore.shared.set(bundleID: edit.bundleID, appName: edit.appName, target: edit.target)
        // 设置规则后，把这个 App 已打开的窗口也立即搬过去
        if edit.target != nil {
            WindowMover.shared.moveExistingWindows(bundleID: edit.bundleID)
        }
    }

    @objc private func applyAll() {
        WindowMover.shared.applyToAllExistingWindows()
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([RuleStore.shared.configFileURL])
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        promptForPermission()
    }
}
