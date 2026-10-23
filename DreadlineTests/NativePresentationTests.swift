import XCTest
import AppKit

@MainActor
final class NativePresentationTests: XCTestCase {
    private func model(setUp: Bool = true, trusted: Bool = true) -> AppModel {
        let store = MemoryStore()
        if setUp { store.db.preferences.onboardingComplete = true; store.db.preferences.selectedCalendars = ["c"] }
        let access = FakeWorkspaceAccess(); access.trusted = trusted
        let notifications = FakeNotifications(); notifications.allowed = setUp
        return AppModel(store: store, source: FakeSource(), notificationSink: notifications, startServices: false, windowAccess: access)
    }
    func testMenuShowsOnboardingUntilSetupIsComplete() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model(setUp: false)
        let menu = MenuBarController(model: model)
        defer { menu.close() }
        try await Task.sleep(for: .milliseconds(150))
        menu.show()
        XCTAssertFalse(menu.popover.isShown, "The app stays locked before setup")
        XCTAssertTrue(menu.onboardingWindow?.isVisible == true)
        menu.openSettings()
        XCTAssertNil(menu.settingsWindow, "Settings are locked too")
    }
    func testFullscreenPreviewOwnsAVisibleScreenSizedPanelAndEscapeClosesIt() throws {
        let app = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        defer { model.endDemo(resumeDelivery: false) }
        model.startDemo(.fullscreen)
        let panel = try XCTUnwrap(app.windows.first { $0.title == "Dreadline reminder" && $0.isVisible })
        XCTAssertTrue(NSScreen.screens.contains { $0.frame == panel.frame })
        XCTAssertEqual(panel.contentView?.frame.size, panel.frame.size)
        XCTAssertTrue(model.overlayStatus.contains("visible"))
        panel.cancelOperation(nil)
        XCTAssertFalse(model.demoActive)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(model.overlayStatus, "Idle")
    }
    func testPreludePreviewAutomaticallyReleasesItsOwnedWindows() async throws {
        let app = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        defer { model.endDemo(resumeDelivery: false) }
        model.startDemo(.gentle)
        let panel = try XCTUnwrap(app.windows.first { $0.title == "Dreadline reminder" && $0.isVisible })
        XCTAssertTrue(model.demoActive)
        try await Task.sleep(for: .milliseconds(4500))
        XCTAssertFalse(model.demoActive)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(model.overlayStatus, "Idle")
    }

    func testViewMeetingRequestOpensTheMenuPopover() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        let menu = MenuBarController(model: model)
        defer { menu.close() }
        // AppKit attaches a newly registered status item on its next event turn.
        try await Task.sleep(for: .milliseconds(150))
        guard menu.statusItem.button?.window?.isVisible == true else {
            throw XCTSkip("The test host has no visible menu-bar slot")
        }
        XCTAssertNil(menu.settingsWindow)
        model.showMain()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(menu.popover.isShown)
        model.showEditor = true
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(menu.popover.isShown, "Opening the inline editor must keep its popover visible")
        model.showEditor = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(menu.popover.isShown, "Returning from the editor must keep its popover visible")
        XCTAssertEqual(menu.popover.contentSize.width, MainView.width)
        XCTAssertLessThanOrEqual(menu.popover.contentSize.height, 560)
        XCTAssertNil(menu.settingsWindow)
        XCTAssertFalse(menu.popoverShouldDetach(menu.popover))
    }

    func testSettingsClosesPopoverAndReusesTheOnlyStandaloneWindow() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        await model.refreshNotificationStatus()
        let menu = MenuBarController(model: model)
        defer { menu.close() }
        menu.show()
        menu.openSettings()
        let window = try XCTUnwrap(menu.settingsWindow)
        XCTAssertFalse(menu.popover.isShown)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.title, "Dreadline Settings")
        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 560, height: 580))
        window.close()
        menu.openSettings(section: "Haunting")
        XCTAssertTrue(menu.settingsWindow === window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(menu.model.settingsTab, "Haunting")
    }
}

extension NativePresentationTests {
    func testNewPreviewSurvivesAnOlderAnimatedRelease() async throws {
        let app = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        defer { model.endDemo(resumeDelivery: false) }
        model.startDemo(.fullscreen)
        let old = try XCTUnwrap(app.windows.first { $0.title == "Dreadline reminder" && $0.isVisible })
        model.endDemo(resumeDelivery: false, animated: true)
        model.startDemo(.fullscreen)
        let next = try XCTUnwrap(app.windows.first { $0.title == "Dreadline reminder" && $0.isVisible })
        XCTAssertFalse(old === next)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertTrue(next.isVisible)
        XCTAssertTrue(model.demoActive)
    }
    func testEscapeDuringAnimatedReleaseIsImmediateAndLeavesNoError() throws {
        let app = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let model = model()
        defer { model.endDemo(resumeDelivery: false) }
        model.startDemo(.fullscreen)
        let panel = try XCTUnwrap(app.windows.first { $0.title == "Dreadline reminder" && $0.isVisible })
        model.endDemo(resumeDelivery: false, animated: true)
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(model.error)
    }
}

extension NativePresentationTests {
    func testPreludeWatchdogReleasesTheLatestUpdatedQueue() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a macOS display session") }
        let clock = FakeClock(Date())
        let model = AppModel(store: MemoryStore(), source: FakeSource(), notificationSink: FakeNotifications(), startServices: false, deadlineDriver: FakeDeadlineDriver(), clock: clock, windowAccess: FakeWorkspaceAccess())
        defer { model.overlay.close() }
        var prefs = model.preferences; prefs.alertsEnabled = true; model.updatePreferences(prefs)
        model.addOrEdit(LocalReminder(title: "First", due: clock.now + 300))
        model.addOrEdit(LocalReminder(title: "Second", due: clock.now + 300))
        XCTAssertEqual(model.unresolved.count, 2)
        try await Task.sleep(for: .milliseconds(4500))
        XCTAssertTrue(model.unresolved.allSatisfy { $0.preludeUntil == nil })
        XCTAssertEqual(model.overlayStatus, "Idle")
    }
}
