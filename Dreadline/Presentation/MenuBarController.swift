import AppKit
import SwiftUI
import Combine

/// The agenda has one home: the popover anchored to the status item.
/// Until setup is complete, every entry point opens onboarding instead.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    let model: AppModel
    let statusItem: NSStatusItem
    let popover = NSPopover()
    private(set) var settingsWindow: NSWindow?
    private(set) var onboardingWindow: NSWindow?
    private var changes: AnyCancellable?
    private var displayedPause: Bool?
    private var ticker: Timer?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView:
            MainView(model: model, openSettings: { [weak self] section in self?.openSettings(section: section) }, closeMenu: { [weak self] in self?.popover.performClose(nil) })
        )
        // The popover follows the agenda's height instead of leaving empty space.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.imagePosition = .imageLeading
        NotificationCenter.default.addObserver(self, selector: #selector(show), name: .showDreadline, object: nil)
        changes = model.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        updateStatus()
        // First launch, or a required permission was revoked: start with setup.
        if !model.setupComplete { DispatchQueue.main.async { [weak self] in self?.showOnboarding() } }
    }

    private func updateStatus() {
        // Updating an anchored status item can dismiss its transient popover.
        // Keep the anchor stable during editing; catch up after it closes.
        guard !popover.isShown else { return }
        guard let button = statusItem.button else { return }
        if displayedPause != model.db.paused {
            let image = model.db.paused
                ? NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Paused")
                : Bundle.main.url(forResource: "GhostTemplate", withExtension: "pdf").flatMap(NSImage.init(contentsOf:))
            image?.size = NSSize(width: 22, height: 22)
            image?.isTemplate = true
            button.image = image
            displayedPause = model.db.paused
        }
        let title = " " + model.menuTitle
        if button.title != title { button.title = title }
        button.setAccessibilityLabel("Dreadline")
        button.toolTip = "Dreadline — agenda and reminders"
    }

    @objc private func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    @objc func show() {
        guard model.setupComplete else { showOnboarding(); return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
    }

    func showOnboarding() {
        popover.performClose(nil)
        model.refreshPermissions()
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Set up Dreadline"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, onFinish: { [weak self] in self?.finishOnboarding() }))
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    private func finishOnboarding() {
        model.completeSetup()
        guard model.setupComplete else { return }
        onboardingWindow?.close()
        show()
    }

    func openSettings(section: String? = nil) {
        guard model.setupComplete else { showOnboarding(); return }
        if let section { model.settingsTab = section }
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 580), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Dreadline Settings"
            // The tab bar sits in the title bar area, like a native settings window.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model).frame(width: 560, height: 580))
            window.setContentSize(NSSize(width: 560, height: 580))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func popoverDidClose(_ notification: Notification) { updateStatus() }

    func close() {
        changes?.cancel()
        ticker?.invalidate()
        ticker = nil
        NotificationCenter.default.removeObserver(self)
        popover.performClose(nil)
        settingsWindow?.close()
        onboardingWindow?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
