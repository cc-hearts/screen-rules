import Cocoa
import ApplicationServices

/// 私有但存在多年的 API：从 AXUIElement 拿 CGWindowID，用来识别“同一个窗口”
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 监听有规则的 App 的窗口动向，把窗口搬到目标屏 / 调整到设定尺寸。
///
/// 语义：**每个窗口只归位一次**。新窗口出现时（AX 事件，或激活时盘点到没见过的窗口）
/// 执行规则；之后用户手动移动/调整不再干预。唯一会重复执行的是用户显式触发：
/// 菜单里改规则、或点「立即按规则整理所有窗口」。
final class WindowMover {
    static let shared = WindowMover()
    private var observers: [pid_t: AXObserver] = [:]
    /// 已执行过规则的窗口（按所属 pid 分组），避免重复归位
    private var enforcedWindows: [pid_t: Set<CGWindowID>] = [:]
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        for app in apps { attach(pid: app.processIdentifier, name: app.localizedName) }
        SRLog.log("watcher started, attached \(observers.count)/\(apps.count) apps")
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(pid: app.processIdentifier, name: app.localizedName)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        observers.removeValue(forKey: app.processIdentifier)
        enforcedWindows.removeValue(forKey: app.processIdentifier)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              RuleStore.shared.rule(for: bundleID) != nil else { return }
        let pid = app.processIdentifier
        let name = app.localizedName ?? bundleID
        // 激活时只盘点「没处理过」的窗口：ScreenRules 启动前已存在的、或 AX 事件漏掉的
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.enforceUnseenWindows(pid: pid, name: name)
        }
    }

    private func enforceUnseenWindows(pid: pid_t, name: String) {
        for w in axWindows(pid: pid) {
            guard let wid = windowID(of: w) else { continue }
            guard !enforcedWindows[pid, default: []].contains(wid) else { continue }
            enforcedWindows[pid, default: []].insert(wid)
            let result = applyRule(pid: pid, window: w)
            if result.shouldLog {
                SRLog.log("activation(new window): \(name) -> \(result)")
            }
        }
    }

    private func attach(pid: pid_t, name: String?, isRetry: Bool = false) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let createErr = AXObserverCreate(pid, windowCreatedCallback, &observer)
        guard createErr == .success, let observer else {
            SRLog.log("attach FAILED(create \(createErr.rawValue)): \(name ?? "?") pid=\(pid)")
            return
        }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        guard err == .success else {
            if !isRetry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.attach(pid: pid, name: name, isRetry: true)
                }
            } else {
                SRLog.log("attach FAILED(add \(err.rawValue)): \(name ?? "?") pid=\(pid)")
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        SRLog.log("attached: \(name ?? "?") pid=\(pid)")
    }

    fileprivate func handleWindowCreated(pid: pid_t, window: AXUIElement) {
        if let wid = windowID(of: window) {
            guard !enforcedWindows[pid, default: []].contains(wid) else { return }
            enforcedWindows[pid, default: []].insert(wid)
        }
        // 两轮修正：很多 App 创建窗口后还会自己调整一次位置/尺寸（比如 Dock 点击触发的展示逻辑）
        for delay in [0.25, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
                let result = self.applyRule(pid: pid, window: window)
                if result.shouldLog {
                    SRLog.log("window-created+\(delay)s: \(name) pid=\(pid) -> \(result)")
                }
            }
        }
    }

    enum MoveResult: CustomStringConvertible {
        case skipped               // 非标准窗口（输入法候选框/对话框/面板等），不处理
        case moved(from: String, to: String)
        case resized(Int)            // 缩放百分比
        case alreadyThere
        case noRule
        case noTargetDisplay
        case axFailed(String)

        var shouldLog: Bool {
            switch self {
            case .noRule, .skipped: return false
            default: return true
            }
        }

        var description: String {
            switch self {
            case .skipped:           return "skipped"
            case .moved(let f, let t): return "moved \(f) -> \(t)"
            case .resized(let p):      return "resized to \(p)%"
            case .alreadyThere:       return "already ok"
            case .noRule:             return "no rule"
            case .noTargetDisplay:    return "target display not found"
            case .axFailed(let s):    return "AX failed: \(s)"
            }
        }
    }

    @discardableResult
    func applyRule(pid: pid_t, window: AXUIElement) -> MoveResult {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              let rule = RuleStore.shared.rule(for: bundleID) else { return .noRule }
        return apply(rule: rule, to: window)
    }

    /// 对单个窗口应用规则：先搬屏（如有 target），再调尺寸（如有 scale）
    private func apply(rule: Rule, to window: AXUIElement) -> MoveResult {
        guard shouldManage(window) else { return .skipped }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        let posErr = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        let sizeErr = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard posErr == .success, sizeErr == .success else {
            return .axFailed("read pos=\(posErr.rawValue) size=\(sizeErr.rawValue)")
        }
        var axPos = CGPoint.zero
        var axSize = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &axPos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &axSize)
        guard axSize.width > 0, axSize.height > 0 else { return .axFailed("zero size") }

        let rect = DisplayManager.axToCocoa(CGRect(origin: axPos, size: axSize))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let current = DisplayManager.display(containingCocoaPoint: center) else {
            return .axFailed("current display not found")
        }

        // 目标屏：规则指定则用之，否则用窗口当前所在屏（只调尺寸的场景）
        let target = rule.target.flatMap { DisplayManager.resolve($0) } ?? current
        if rule.target != nil && target.id == current.id && rule.scale == nil { return .alreadyThere }

        let tv = target.visibleFrame
        var newRect: CGRect
        if let scale = rule.scale {
            let clamped = min(max(scale, 0.1), 1.0)
            let w = tv.width * clamped
            let h = tv.height * clamped
            // 已在目标屏且尺寸已符合 -> 不动
            if target.id == current.id,
               abs(rect.width - w) < 4, abs(rect.height - h) < 4,
               abs(rect.midX - tv.midX) < 4, abs(rect.midY - tv.midY) < 4 {
                return .alreadyThere
            }
            newRect = CGRect(x: tv.midX - w / 2, y: tv.midY - h / 2, width: w, height: h)
        } else {
            // 保持尺寸，按“相对位置比例”映射到目标屏，并夹取到可见区域内
            let cv = current.visibleFrame
            let rx = cv.width  > 0 ? (rect.minX - cv.minX) / cv.width  : 0
            let ry = cv.height > 0 ? (rect.minY - cv.minY) / cv.height : 0
            let w = min(rect.width, tv.width)
            let h = min(rect.height, tv.height)
            newRect = CGRect(x: tv.minX + rx * tv.width,
                             y: tv.minY + ry * tv.height,
                             width: w, height: h)
            newRect.origin.x = min(max(newRect.minX, tv.minX), tv.maxX - w)
            newRect.origin.y = min(max(newRect.minY, tv.minY), tv.maxY - h)
        }

        let ax = DisplayManager.cocoaToAX(newRect)
        var p = ax.origin
        var s = ax.size
        guard let pv = AXValueCreate(.cgPoint, &p), let sv = AXValueCreate(.cgSize, &s) else {
            return .axFailed("AXValueCreate")
        }
        // 先设尺寸再设位置：有些 App 对位置设置有边界校验，先改尺寸可减少被夹取的概率
        let ss = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        let sp = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        guard sp == .success else {
            return .axFailed("write pos=\(sp.rawValue) size=\(ss.rawValue)")
        }
        if target.id != current.id { return .moved(from: current.name, to: target.name) }
        if rule.scale != nil { return .resized(Int((rule.scale ?? 1) * 100)) }
        return .alreadyThere
    }

    /// 只管理「正常主窗口」。输入法候选框、对话框、抽屉、浮动面板等一律跳过——
    /// 它们会被系统/宿主 App 自己定位（比如候选框跟随光标），我们插手只会添乱。
    /// 读不出 subrole 时保守跳过。
    private func shouldManage(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) == .success,
              (roleRef as? String) == kAXWindowRole else { return false }
        var subRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subRef) == .success,
              (subRef as? String) == "AXStandardWindow" else { return false }
        return true
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(element, &wid) == .success ? wid : nil
    }

    private func axWindows(pid: pid_t) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    /// 显式触发（菜单改规则 / 立即整理）：把某个 App 所有已打开的窗口重新归位。
    /// App 未运行则明确跳过——绝不启动它。
    func moveExistingWindows(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }) else {
            SRLog.log("move-existing: \(bundleID) skipped (not running)")
            return
        }
        let pid = app.processIdentifier
        for w in axWindows(pid: pid) {
            if let wid = windowID(of: w) { enforcedWindows[pid, default: []].insert(wid) }
            let result = applyRule(pid: pid, window: w)
            SRLog.log("move-existing: \(app.localizedName ?? bundleID) -> \(result)")
        }
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
