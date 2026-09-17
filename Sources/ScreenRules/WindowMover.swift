import Cocoa
import ApplicationServices

/// 监听所有 App 的“新窗口创建”事件，命中规则就把窗口搬到目标屏。
final class WindowMover {
    static let shared = WindowMover()
    private var observers: [pid_t: AXObserver] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(pid: app.processIdentifier)
        }
        NSLog("ScreenRules: started, watching \(observers.count) apps")
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(pid: app.processIdentifier)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observers.removeValue(forKey: app.processIdentifier)
    }

    private func attach(pid: pid_t, isRetry: Bool = false) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, windowCreatedCallback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        guard err == .success else {
            // App 刚启动时 AX 可能还没就绪，1 秒后重试一次
            if !isRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.attach(pid: pid, isRetry: true)
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    fileprivate func handleWindowCreated(pid: pid_t, window: AXUIElement) {
        // 稍等片刻再搬：很多 App 创建窗口后还会自己调整一次位置/尺寸
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.applyRule(pid: pid, window: window)
        }
    }

    func applyRule(pid: pid_t, window: AXUIElement) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              let rule = RuleStore.shared.rule(for: bundleID),
              let target = DisplayManager.resolve(rule.target) else { return }
        move(window: window, to: target)
    }

    /// 把窗口搬到目标屏：保持尺寸和“相对位置比例”，并夹取到可见区域内
    func move(window: AXUIElement, to target: DisplayInfo) {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return }
        var axPos = CGPoint.zero
        var axSize = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &axPos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &axSize)
        guard axSize.width > 0, axSize.height > 0 else { return }

        let rect = DisplayManager.axToCocoa(CGRect(origin: axPos, size: axSize))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let current = DisplayManager.display(containingCocoaPoint: center),
              current.id != target.id else { return }   // 已在目标屏

        let cv = current.visibleFrame
        let tv = target.visibleFrame
        let rx = cv.width  > 0 ? (rect.minX - cv.minX) / cv.width  : 0
        let ry = cv.height > 0 ? (rect.minY - cv.minY) / cv.height : 0
        let w = min(rect.width, tv.width)
        let h = min(rect.height, tv.height)
        var newRect = CGRect(x: tv.minX + rx * tv.width,
                             y: tv.minY + ry * tv.height,
                             width: w, height: h)
        newRect.origin.x = min(max(newRect.minX, tv.minX), tv.maxX - w)
        newRect.origin.y = min(max(newRect.minY, tv.minY), tv.maxY - h)

        let ax = DisplayManager.cocoaToAX(newRect)
        var p = ax.origin
        var s = ax.size
        if let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        }
    }

    /// 把某个 App 所有已打开的窗口都按规则搬过去（设置规则时立即生效）
    func moveExistingWindows(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for w in windows { applyRule(pid: app.processIdentifier, window: w) }
    }

    /// 一键整理：所有有规则的 App，把已打开的窗口全部归位
    func applyToAllExistingWindows() {
        for rule in RuleStore.shared.sortedRules {
            moveExistingWindows(bundleID: rule.bundleID)
        }
    }
}

private func windowCreatedCallback(observer: AXObserver, element: AXUIElement,
                                   notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let mover = Unmanaged<WindowMover>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    mover.handleWindowCreated(pid: pid, window: element)
}
