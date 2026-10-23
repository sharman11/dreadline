import XCTest
import Foundation
import EventKit

@MainActor
final class FakeSource: SourceAdapter {
    var results: [SourceKind: SourceResult] = [:]
    var failures = Set<SourceKind>()
    var completionFails = false
    var completions: [UUID] = []
    var pending: CheckedContinuation<SourceResult, Error>?
    var holdCalendar = false
    func status(_ kind: SourceKind) -> EKAuthorizationStatus { failures.contains(kind) ? .denied : .fullAccess }
    func request(_ kind: SourceKind) async throws -> Bool { !failures.contains(kind) }
    func fetch(kind: SourceKind, preferences: Preferences, now: Date) async throws -> SourceResult {
        if failures.contains(kind) { throw DomainError.invalid("fixture fetch failed") }
        if kind == .calendar && holdCalendar {
            holdCalendar = false
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return results[kind] ?? SourceResult(kind: kind, sources: [], items: [])
    }
    func complete(_ item: Occurrence) throws {
        if completionFails { throw DomainError.invalid("fixture write failed") }
        completions.append(item.id)
    }
}
@MainActor
final class FakeNotifications: NotificationSink {
    var onAction: ((String, String) -> Void)?
    var cancels = 0
    var last: Database?
    var allowed = false
    func request() async throws -> Bool { allowed }
    func authorization() async -> String { allowed ? "Authorized" : "Denied" }
    func cancel() { cancels += 1; last = nil }
    func reconcile(_ db: Database, now: Date) async { last = db }
}
@MainActor
final class FakePresenter: PresentationSink {
    var current: Presentation?
    var closes = 0
    func present(_ presentation: Presentation?, demo: Bool) { current = presentation }
    func close() { closes += 1; current = nil }
}
@MainActor
final class DeferringPresenter: PresentationSink {
    var current: Presentation?
    var farewells: [HauntFarewell] = []
    private var pending: (@MainActor () -> Void)?
    func present(_ presentation: Presentation?, demo: Bool) { current = presentation }
    func close() { current = nil }
    func farewell(_ kind: HauntFarewell, then: @escaping @MainActor () -> Void) { farewells.append(kind); pending = then }
    func finish() { let next = pending; pending = nil; next?() }
}
@MainActor
final class IntegrationTests: XCTestCase {
    func testCompletedOneOffLeavesActiveRemindersWhileRepeatingReminderStays() throws {
        let (model, _, _, _, _, clock) = fixture()
        let oneOff = LocalReminder(title: "One off", due: clock.now + 3600)
        model.addOrEdit(oneOff)
        XCTAssertTrue(model.activeLocalReminders.contains { $0.id == oneOff.id })
        let occurrence = try XCTUnwrap(model.unresolved.first { $0.seriesID == oneOff.id })
        model.act(.done, occurrence)
        XCTAssertFalse(model.activeLocalReminders.contains { $0.id == oneOff.id })
        XCTAssertTrue(model.history.contains { $0.id == occurrence.id })

        var repeating = LocalReminder(title: "Repeating", due: clock.now + 7200)
        repeating.recurrence.frequency = .daily
        model.addOrEdit(repeating)
        let repeatOccurrence = try XCTUnwrap(model.unresolved.first { $0.seriesID == repeating.id })
        model.act(.done, repeatOccurrence)
        XCTAssertTrue(model.activeLocalReminders.contains { $0.id == repeating.id })
        XCTAssertTrue(model.unresolved.contains { $0.seriesID == repeating.id && $0.id != repeatOccurrence.id })
    }

    // Regression: editing a repeating reminder keeps its pending occurrence instead of reverting to the first date.
    func testEditingRepeatingSeriesTitleKeepsPendingDueTime() throws {
        let (model, _, _, _, _, clock) = fixture()
        var series = LocalReminder(title: "Stretch", due: clock.now + 3600)
        series.recurrence.frequency = .daily
        model.addOrEdit(series)
        let pendingDue = try XCTUnwrap(model.unresolved.first { $0.seriesID == series.id }?.due)
        clock.now += 86400 * 3
        model.addOrEdit({ var edit = series; edit.title = "Stretch more"; return edit }())
        let active = model.unresolved.filter { $0.seriesID == series.id }
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].title, "Stretch more")
        XCTAssertEqual(active[0].due, pendingDue)
    }
    func testChangingScheduleOfStartedSeriesBeginsAtNextFutureDate() throws {
        let (model, _, _, _, _, clock) = fixture()
        var series = LocalReminder(title: "Water plants", due: clock.now + 60)
        series.recurrence.frequency = .daily
        model.addOrEdit(series)
        clock.now += 86400 * 3
        var edit = series; edit.recurrence.frequency = .weekly
        model.addOrEdit(edit)
        let due = try XCTUnwrap(model.unresolved.first { $0.seriesID == series.id }?.due)
        XCTAssertGreaterThan(due, clock.now)
    }
    func testSnoozeUsesPreferredLength() throws {
        let (model, _, _, _, _, clock) = fixture()
        var local = LocalReminder(title: "Call back", due: clock.now)
        local.snoozeMinutes = 20
        model.addOrEdit(local)
        let item = try XCTUnwrap(model.unresolved.first)
        XCTAssertEqual(model.snoozeLabel(item), "Snooze 20 min")
        model.escape(item)
        let until = try XCTUnwrap(model.db.occurrences.first { $0.id == item.id }?.snoozeUntil)
        XCTAssertEqual(until.timeIntervalSinceNow, 1200, accuracy: 5)
        var p = model.preferences; p.snoozeMinutes = 10; model.updatePreferences(p)
        XCTAssertEqual(model.snoozeInterval(event(clock.now)), 600)
    }
    // Regression: a routine refresh (menu click, timer, sync) must not tear down an alert on screen.
    func testRoutineRefreshKeepsVisibleAlert() async {
        let (model, _, source, _, presenter, clock) = fixture()
        var p = model.preferences; p.selectedCalendars = ["c"]; model.updatePreferences(p)
        source.results[.calendar] = calendarResult([event(clock.now)])
        await model.refresh(catchUp: false)
        XCTAssertEqual(presenter.current?.items.count, 1)
        let closes = presenter.closes
        await model.refresh(catchUp: false)
        model.scheduleRefresh()
        XCTAssertEqual(presenter.closes, closes)
        XCTAssertEqual(presenter.current?.items.count, 1)
    }
    func testOverlayDismissAppliesOnlyAfterTheWarningFinishes() throws {
        let presenter = DeferringPresenter(), memory = MemoryStore(), clock = FakeClock(Date())
        memory.db.preferences.alertsEnabled = true
        let model = AppModel(store: memory, source: FakeSource(), notificationSink: FakeNotifications(), presentationSink: presenter, startServices: false, clock: clock)
        model.addOrEdit(LocalReminder(title: "Haunted", due: clock.now))
        let item = try XCTUnwrap(model.unresolved.first)
        model.dismissFromOverlay(item)
        XCTAssertEqual(presenter.farewells, [.dismiss])
        XCTAssertFalse(model.db.occurrences[0].state.terminal, "The action waits for the exit to play")
        presenter.finish()
        XCTAssertEqual(model.db.occurrences[0].state, .acknowledged)
    }
    func testOverlaySnoozeAppliesOnlyAfterTheFlickerWarning() throws {
        let presenter = DeferringPresenter(), memory = MemoryStore(), clock = FakeClock(Date())
        memory.db.preferences.alertsEnabled = true
        let model = AppModel(store: memory, source: FakeSource(), notificationSink: FakeNotifications(), presentationSink: presenter, startServices: false, clock: clock)
        model.addOrEdit(LocalReminder(title: "Haunted", due: clock.now))
        let item = try XCTUnwrap(model.unresolved.first)
        model.snoozeFromOverlay([item])
        XCTAssertEqual(presenter.farewells, [.snooze])
        XCTAssertNotEqual(model.db.occurrences[0].state, .snoozed)
        presenter.finish()
        XCTAssertEqual(model.db.occurrences[0].state, .snoozed)
    }
    func testJoiningItemIsKeptOffScreenDuringBrowserHandoff() {
        let item = event(Date())
        var other = event(Date()); other.id = UUID()
        let presentation = Presentation(items: [item, other], intensity: .fullscreen, catchUp: false)
        XCTAssertEqual(AppModel.excluding([item.id], from: presentation)?.items.map(\.id), [other.id])
        XCTAssertNil(AppModel.excluding([item.id, other.id], from: presentation))
        XCTAssertEqual(AppModel.excluding([], from: presentation), presentation)
    }
    func testSetupNeedsCalendarAccessACalendarWindowControlAndNotifications() async {
        let access = FakeWorkspaceAccess(); access.trusted = false
        let source = FakeSource(), notifications = FakeNotifications()
        let model = AppModel(store: MemoryStore(), source: source, notificationSink: notifications, presentationSink: FakePresenter(), startServices: false, windowAccess: access)
        XCTAssertTrue(model.calendarAccessGranted)
        XCTAssertFalse(model.requiredSetupDone, "No calendar chosen and no window control")
        model.setCalendar("c", selected: true)
        XCTAssertFalse(model.requiredSetupDone, "Window control still missing")
        model.completeSetup()
        XCTAssertFalse(model.setupComplete, "Cannot finish while a requirement is missing")
        access.trusted = true; model.refreshPermissions()
        await model.refreshNotificationStatus()
        XCTAssertFalse(model.requiredSetupDone, "Notifications still missing")
        XCTAssertEqual(model.menuTitle, "Finish setup")
        notifications.allowed = true
        await model.refreshNotificationStatus()
        XCTAssertTrue(model.requiredSetupDone)
        model.completeSetup()
        XCTAssertTrue(model.setupComplete)
        XCTAssertTrue(model.preferences.alertsEnabled, "Finishing setup turns alerts on")
        source.failures.insert(.calendar); model.refreshPermissions()
        XCTAssertFalse(model.setupComplete, "Revoking a permission locks the app again")
    }
    func fixture() -> (AppModel, MemoryStore, FakeSource, FakeNotifications, FakePresenter, FakeClock) {
        let memory = MemoryStore(); memory.db.preferences.alertsEnabled = true
        let source = FakeSource(), notifications = FakeNotifications(), presenter = FakePresenter(), clock = FakeClock(Date())
        let model = AppModel(store: memory, source: source, notificationSink: notifications, presentationSink: presenter, startServices: false, clock: clock)
        return (model, memory, source, notifications, presenter, clock)
    }
    func event(_ now: Date) -> Occurrence { Occurrence(kind: .calendar, sourceID: "c", sourceName: "Mock", providerID: "p", title: "Private title", due: now, end: now + 600) }
    func calendarResult(_ items: [Occurrence]) -> SourceResult {
        SourceResult(kind: .calendar, sources: [SourceSnapshot(id: "c", accountID: "", name: "Mock", provider: "Fake", kind: .calendar, writable: false)], items: items)
    }
    func testFailedSaveKeepsPresentationAndPendingState() {
        let (model, store, _, _, presenter, clock) = fixture()
        let reminder = LocalReminder(title: "Local fixture", due: clock.now)
        model.addOrEdit(reminder)
        XCTAssertEqual(presenter.current?.items.count, 1)
        let item = model.unresolved[0]
        store.fail = true
        model.act(.done, item)
        XCTAssertFalse(model.db.occurrences[0].state.terminal)
        XCTAssertEqual(presenter.current?.items.first?.id, item.id)
        XCTAssertNotNil(model.error)
        store.fail = false
        model.act(.done, item)
        XCTAssertEqual(model.db.occurrences[0].state, .completed)
        XCTAssertNil(presenter.current)
    }
    func testFetchFailurePreservesSnapshotsButSuppressesDelivery() async {
        let (model, _, source, notifications, presenter, clock) = fixture()
        var p = model.preferences; p.selectedCalendars = ["c"]; model.updatePreferences(p)
        source.results[.calendar] = calendarResult([event(clock.now)])
        await model.refresh(catchUp: false)
        XCTAssertEqual(presenter.current?.items.count, 1)
        let original = model.db.occurrences[0].id
        source.failures.insert(.calendar)
        await model.refresh(catchUp: false)
        XCTAssertEqual(model.db.occurrences[0].id, original)
        XCTAssertFalse(model.db.occurrences[0].state.terminal)
        XCTAssertNil(presenter.current)
        XCTAssertGreaterThan(notifications.cancels, 0)
        source.failures.remove(.calendar); source.results[.calendar] = calendarResult([])
        await model.refresh(catchUp: false)
        XCTAssertEqual(model.db.occurrences[0].state, .cancelled)
    }
    func testNewerRefreshDiscardsStaleResult() async {
        let (model, _, source, _, _, clock) = fixture()
        var p = model.preferences; p.selectedCalendars = ["c"]; model.updatePreferences(p)
        source.holdCalendar = true
        let old = Task { await model.refresh(catchUp: false) }
        for _ in 0..<100 where source.pending == nil { await Task.yield() }
        XCTAssertNotNil(source.pending)
        var latest = event(clock.now); latest.providerID = "latest"
        source.results[.calendar] = calendarResult([latest])
        await model.refresh(catchUp: false)
        source.pending?.resume(returning: calendarResult([event(clock.now)])); source.pending = nil
        await old.value
        XCTAssertEqual(model.unresolved.map(\.providerID), ["latest"])
    }
    func testAppleCompletionFailureRetainsPendingAndOffersLocalAck() async {
        let (model, _, source, _, presenter, clock) = fixture()
        var item = event(clock.now); item.kind = .reminders
        var p = model.preferences; p.selectedLists = ["c"]; model.updatePreferences(p)
        source.results[.reminders] = SourceResult(kind: .reminders, sources: [SourceSnapshot(id: "c", accountID: "", name: "Mock", provider: "Fake", kind: .reminders, writable: true)], items: [item])
        await model.refresh(catchUp: false)
        source.completionFails = true
        model.act(.done, model.unresolved[0])
        XCTAssertFalse(model.db.occurrences[0].state.terminal)
        XCTAssertNotNil(presenter.current)
        model.act(.acknowledge, model.unresolved[0])
        XCTAssertEqual(model.db.occurrences[0].state, .acknowledged)
        XCTAssertTrue(source.completions.isEmpty)
    }
    func testPauseQuietAndNotificationGateUseSamePolicy() async {
        let (model, _, _, notifications, presenter, clock) = fixture()
        model.addOrEdit(LocalReminder(title: "Fixture", due: clock.now))
        XCTAssertNotNil(presenter.current)
        model.pause(until: nil)
        XCTAssertNil(presenter.current)
        XCTAssertTrue(model.db.paused)
        await Task.yield()
        XCTAssertTrue(notifications.last?.paused == true || notifications.last == nil)
        var p = model.preferences; p.quiet = QuietHours(enabled: true, startMinute: 0, endMinute: 0)
        model.updatePreferences(p)
        model.resume(); await model.refresh(catchUp: true)
        XCTAssertNil(presenter.current)
        XCTAssertFalse(model.db.occurrences[0].state.terminal)
    }
    func testDemoUsesNoProductionLedger() {
        let (model, store, _, _, presenter, _) = fixture()
        let original = store.db
        model.startDemo(.fullscreen)
        XCTAssertTrue(model.demoActive)
        XCTAssertNotNil(presenter.current)
        model.escapeAll(presenter.current!.items)
        XCTAssertFalse(model.demoActive)
        XCTAssertNil(presenter.current)
        XCTAssertEqual(store.db, original)
    }
    func testRestartDoesNotResurrectSavedAcknowledgement() {
        let (model, store, source, notifications, presenter, clock) = fixture()
        model.addOrEdit(LocalReminder(title: "Fixture", due: clock.now))
        model.act(.acknowledge, model.unresolved[0])
        let restartPresenter = FakePresenter()
        let restarted = AppModel(store: store, source: source, notificationSink: notifications, presentationSink: restartPresenter, startServices: false, clock: clock)
        restarted.tick(catchUp: true)
        XCTAssertNil(restartPresenter.current)
        XCTAssertEqual(restarted.history.count, 1)
        XCTAssertNil(presenter.current)
    }
}

@MainActor
final class FakeDeadlineDriver: DeadlineDriver {
    var deadline: Date?
    var action: (@MainActor () -> Void)?
    var schedules = 0
    func schedule(at date: Date?, action: @escaping @MainActor () -> Void) { deadline = date; self.action = action; schedules += 1 }
    func cancel() { deadline = nil; action = nil }
    func fire() { let callback = action; action = nil; callback?() }
}
extension IntegrationTests {
    func testInjectedSingleDeadlineDriverAndQuitCleanup() {
        let store = MemoryStore(), source = FakeSource(), notifications = FakeNotifications(), presenter = FakePresenter(), driver = FakeDeadlineDriver(), clock = FakeClock(Date())
        store.db.preferences.alertsEnabled = true
        store.db.preferences.timing = Timing()
        store.db.preferences.poltergeistEnabled = false
        let model = AppModel(store: store, source: source, notificationSink: notifications, presentationSink: presenter, startServices: false, deadlineDriver: driver, clock: clock)
        model.addOrEdit(LocalReminder(title: "Future", due: clock.now + 1200))
        XCTAssertEqual(driver.deadline, clock.now + 600)
        XCTAssertNil(presenter.current)
        clock.advance(600); driver.fire()
        XCTAssertEqual(presenter.current?.intensity, .gentle)
        XCTAssertEqual(driver.deadline, clock.now + 480)
        model.prepareToQuit(keepNotifications: false)
        XCTAssertNil(driver.deadline)
        XCTAssertNil(presenter.current)
        XCTAssertGreaterThan(notifications.cancels, 0)
    }
    func testSnoozeSkipAndCompletePersistAcrossModelRestart() {
        for action in [Command.snooze(Date() + 300), .skip, .done] {
            let (model, store, source, notifications, _, clock) = fixture()
            model.addOrEdit(LocalReminder(title: "Persist", due: clock.now))
            let item = model.unresolved[0]
            model.act(action, item)
            let presenter = FakePresenter()
            let restarted = AppModel(store: store, source: source, notificationSink: notifications, presentationSink: presenter, startServices: false, clock: clock)
            restarted.tick()
            XCTAssertNil(presenter.current)
            XCTAssertEqual(restarted.db.occurrences[0].state, model.db.occurrences[0].state)
        }
    }
}

extension IntegrationTests {
    func testReturningFromPreludePreservesMeetingTimeAlert() {
        let (model, _, _, _, presenter, clock) = fixture()
        model.addOrEdit(LocalReminder(title: "Fixture", due: clock.now + 300))
        XCTAssertEqual(presenter.current?.phase, .prelude)
        model.stopPresentation(presenter.current!)
        XCTAssertNil(presenter.current)
        XCTAssertFalse(model.unresolved[0].state.terminal)
        clock.advance(300); model.tick()
        XCTAssertEqual(presenter.current?.intensity, .fullscreen)
    }
    func testDemoEndingResumesDueRemindersWithoutJump() {
        let (model, _, _, _, presenter, clock) = fixture()
        model.addOrEdit(LocalReminder(title: "Fixture", due: clock.now + 300))
        model.startDemo()
        clock.advance(300); model.tick()
        model.endDemo()
        XCTAssertEqual(presenter.current?.intensity, .prominent)
        XCTAssertFalse(model.demoActive)
    }
}
