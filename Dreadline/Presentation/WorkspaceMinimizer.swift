import AppKit
import ApplicationServices

// No titles, documents, screenshots or keyboard events are read.
enum WindowChangeResult { case success, gone, failed }
@MainActor
protocol MinimizableWindow: AnyObject {
    var minimized: Bool? { get }
    var canMinimize: Bool { get }
    func setMinimized(_ value: Bool) -> WindowChangeResult
}
@MainActor
protocol WorkspaceWindowAccess {
    var trusted: Bool { get }
    var enumerationIncomplete: Bool { get }
    func requestPermission()
    func windows() -> [any MinimizableWindow]
}

extension WorkspaceWindowAccess { var enumerationIncomplete: Bool { false } }

@MainActor
final class WorkspaceMinimizer {
    private let access: any WorkspaceWindowAccess
    private var owned: [any MinimizableWindow] = []
    private var queued: [any MinimizableWindow] = []
    private var waveSize = 1
    private(set) var skipped = 0
    /// Windows found by the last enumeration (diagnostics only).
    private(set) var found = 0
    var enumerationIncomplete: Bool { access.enumerationIncomplete }
    private(set) var status = "Accessibility permission required to minimize windows."
    var trusted: Bool { access.trusted }
    var pendingRestorations: Int { owned.count }
    init(access: any WorkspaceWindowAccess = AXWorkspaceWindowAccess()) { self.access = access }
    func requestPermission() { access.requestPermission() }
    func minimize() {
        guard prepareMinimize() else { return }
        applyNext(count: queued.count, budget: 1.5)
    }
    @discardableResult
    func prepareMinimize() -> Bool {
        if !owned.isEmpty { restore() }
        queued = []
        guard owned.isEmpty else { status = "Some windows still need restoring. Use Restore windows in Settings."; return false }
        guard access.trusted else { status = "Accessibility permission required — windows were not minimized."; return false }
        skipped = 0
        queued = access.windows()
        found = queued.count
        waveSize = max(1, (queued.count + 2) / 3)
        status = "Window sequence ready."
        return true
    }
    func minimizeNextWave() { applyNext(count: waveSize, budget: 0.5) }
    private func applyNext(count: Int, budget: Double) {
        guard access.trusted else { status = "Accessibility permission required — windows cannot be minimized."; return }
        let amount = min(count, queued.count)
        let candidates = Array(queued.prefix(amount))
        queued.removeFirst(amount)
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        for (index, window) in candidates.enumerated() {
            if ProcessInfo.processInfo.systemUptime >= deadline { skipped += candidates.count - index; break }
            guard let minimized = window.minimized else { skipped += 1; continue }
            if minimized { continue }
            guard window.canMinimize else { skipped += 1; continue }
            switch window.setMinimized(true) {
            case .success: owned.append(window)
            case .failed: skipped += 1
            case .gone: break
            }
        }
        status = "Minimized \(owned.count) window(s)\(skipped > 0 ? "; \(skipped) unsupported or unavailable" : "")."
        if access.enumerationIncomplete { status += " Some apps could not be inspected." }
    }
    func restore() {
        queued = []
        guard !owned.isEmpty else { return }
        guard access.trusted else { status = "Accessibility permission was lost. Re-enable it, then choose Restore windows."; return }
        var remaining: [any MinimizableWindow] = []
        for window in owned {
            // Always send false, even during a pending minimize animation.
            if case .failed = window.setMinimized(false) { remaining.append(window) }
        }
        owned = remaining
        status = remaining.isEmpty ? "Windows restored." : "Could not restore \(remaining.count) window(s). Retry Restore windows in Settings."
    }
}

@MainActor
final class AXWorkspaceWindowAccess: WorkspaceWindowAccess {
    private(set) var enumerationIncomplete = false
    var trusted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func windows() -> [any MinimizableWindow] {
        enumerationIncomplete = false
        guard trusted else { return [] }
        var result: [any MinimizableWindow] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier && !app.isHidden && !app.isTerminated {
            if ProcessInfo.processInfo.systemUptime >= deadline { enumerationIncomplete = true; break }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { enumerationIncomplete = true; continue }
            for window in windows {
                if ProcessInfo.processInfo.systemUptime >= deadline { enumerationIncomplete = true; break }
                AXUIElementSetMessagingTimeout(window, 0.08)
                // Only real windows; Finder's desktop also appears in this list.
                var role: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
                      role as? String == kAXWindowRole as String else { continue }
                result.append(AXMinimizableWindow(element: window, pid: app.processIdentifier, launched: app.launchDate))
            }
        }
        result += (NSApp?.windows ?? []).filter { $0.isVisible && $0.styleMask.contains(.miniaturizable) }.map { OwnMinimizableWindow(window: $0) }
        return result
    }
}

@MainActor
private final class AXMinimizableWindow: MinimizableWindow {
    let element: AXUIElement
    let pid: pid_t
    let launched: Date?
    init(element: AXUIElement, pid: pid_t, launched: Date?) {
        self.element = element; self.pid = pid; self.launched = launched
    }
    var minimized: Bool? { bool(kAXMinimizedAttribute) }
    var canMinimize: Bool {
        if bool("AXFullScreen") == true { return false }
        var writable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &writable) == .success && writable.boolValue
    }
    private func bool(_ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
    func setMinimized(_ value: Bool) -> WindowChangeResult {
        // Apps started by the system at login (such as Finder) have no launch date; only compare when known.
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, app.launchDate == launched else { return .gone }
        let result = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
        switch result {
        case .success: return .success
        case .invalidUIElement: return .gone
        default: return .failed
        }
    }
}

@MainActor
private final class OwnMinimizableWindow: MinimizableWindow {
    weak var window: NSWindow?
    init(window: NSWindow) { self.window = window }
    var minimized: Bool? { window?.isMiniaturized }
    var canMinimize: Bool { window?.styleMask.contains(.miniaturizable) == true && window?.styleMask.contains(.fullScreen) != true }
    func setMinimized(_ value: Bool) -> WindowChangeResult {
        guard let window else { return .gone }
        if !value && !window.isVisible && !window.isMiniaturized { return .gone }
        if value { window.miniaturize(nil) } else { window.deminiaturize(nil) }
        return .success
    }
}
