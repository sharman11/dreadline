import SwiftUI
import AppKit

@main
struct DreadlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.menu?.openSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }

}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?
    private(set) var menu: MenuBarController?
    private var duplicate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy hands off to the running one and never opens the database.
        guard !duplicate else { return }
        let model = AppModel()
        self.model = model
        menu = MenuBarController(model: model)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menu?.show()
        return false
    }

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
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "xyz.dreadline.app").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first { duplicate = true; existing.activate(options: []); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
