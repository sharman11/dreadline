import SwiftUI
import AppKit

@main
struct DreadlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Dreadline", id: "main") { MainView(model: model).onAppear { delegate.model = model } }
            .defaultSize(width: 1060, height: 720)
        MenuBarExtra { MenuView(model: model) } label: { Label(model.menuTitle, systemImage: model.db.paused ? "bell.slash" : "bell.badge") }
            .menuBarExtraStyle(.window)
        Settings { SettingsView(model: model).frame(width: 720, height: 650) }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.quitting else { return .terminateNow }
        var keep = false
        if model.preferences.fallback {
            let alert = NSAlert()
            alert.messageText = "Quit Dreadline?"
            alert.informativeText = "Overlays stop when you quit. Kept system notifications may become stale if source events change."
            alert.addButton(withTitle: "Cancel notifications and quit")
            alert.addButton(withTitle: "Keep notifications and quit")
            alert.addButton(withTitle: "Keep running")
            let response = alert.runModal()
            if response == .alertThirdButtonReturn { return .terminateCancel }
            keep = response == .alertSecondButtonReturn
        }
        model.prepareToQuit(keepNotifications: keep)
        return .terminateNow
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "xyz.dreadline.app").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first { existing.activate(options: []); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
