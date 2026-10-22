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
final class IntegrationTests: XCTestCase {
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
