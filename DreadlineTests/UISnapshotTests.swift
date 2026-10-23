import XCTest
import SwiftUI
import AppKit

/// Renders the main screens to PNGs for visual review. Skipped unless SNAPSHOT_DIR is set
/// (pass TEST_RUNNER_SNAPSHOT_DIR=/path to xcodebuild).
@MainActor
final class UISnapshotTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("SNAPSHOT_DIR not set") }
        dir = URL(fileURLWithPath: path)
    }

    private func model(granted: Bool = true, events: Bool = true) async -> AppModel {
        let store = MemoryStore()
        store.db.preferences.alertsEnabled = true
        store.db.preferences.onboardingComplete = granted
        store.db.preferences.selectedCalendars = granted ? ["work"] : []
        let source = FakeSource()
        if !granted { source.failures = [.calendar] }
        let now = Date()
        let cals = [SourceSnapshot(id: "work", accountID: "", name: "Work", provider: "Google", kind: .calendar, writable: false),
                    SourceSnapshot(id: "home", accountID: "", name: "Family", provider: "iCloud", kind: .calendar, writable: false)]
        let items = events ? [
            Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "1", title: "Design review with the platform team", links: ["https://zoom.us/j/1"], due: now + 720, end: now + 2520),
            Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "2", title: "1:1 with Priya", links: ["https://meet.google.com/abc"], due: now + 5400, end: now + 7200),
            Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "3", title: "Quarterly planning", due: now + 9000, end: now + 12600),
        ] : []
        source.results[.calendar] = SourceResult(kind: .calendar, sources: cals, items: items)
        let access = FakeWorkspaceAccess(); access.trusted = granted
        let notifications = FakeNotifications(); notifications.allowed = granted
        let m = AppModel(store: store, source: source, notificationSink: notifications, presentationSink: FakePresenter(), startServices: false, clock: SystemClock(), windowAccess: access)
        await m.refreshNotificationStatus()
        await m.refresh(catchUp: false)
        return m
    }

    /// A nil size renders the view at its own fitting size, as the popover does.
    private func render<V: View>(_ view: V, _ name: String, size: CGSize? = nil) throws {
        let host = NSHostingView(rootView: view.frame(width: size?.width, height: size?.height))
        let size = size ?? host.fittingSize
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name + ".png"))
    }

    func testRenderScreens() async throws {
        let m = await model()
        try render(MainView(model: m, openSettings: { _ in }, closeMenu: {}), "menu")
        let empty = await model(events: false)
        try render(MainView(model: empty, openSettings: { _ in }, closeMenu: {}), "menu-empty")
        for tab in SettingsView.Tab.allCases {
            m.settingsTab = tab.rawValue
            try render(SettingsView(model: m), "settings-\(tab.rawValue)", size: CGSize(width: 560, height: 580))
        }
        let fresh = await model(granted: false)
        try render(OnboardingView(model: fresh, onFinish: {}), "onboarding", size: CGSize(width: 520, height: 640))
    }
}
