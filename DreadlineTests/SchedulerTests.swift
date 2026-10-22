import XCTest
import Foundation

final class FakeClock: Clock {
    var now: Date
    var uptime: TimeInterval = 100
    init(_ now: Date) { self.now = now }
    func advance(_ interval: Double) { now += interval; uptime += interval }
}
final class MemoryStore: StateStore {
    var db = Database()
    var fail = false
    func load() throws -> Database { db }
    func save(_ database: Database) throws { if fail { throw DomainError.invalid("disk full") }; db = database }
}
final class SchedulerTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ kind: SourceKind = .local, offset: Double = 0) -> Occurrence {
        Occurrence(kind: kind, sourceID: "cal", accountID: "account", sourceName: "Fixture", providerID: UUID().uuidString, title: "Same title", due: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 3600))
    }
    func database(_ items: [Occurrence]) -> Database {
        var db = Database(); db.occurrences = items; db.preferences.alertsEnabled = true
        return db
    }
    func testOrderedEscalationCeilingAndCoincidentStages() throws {
        let clock = FakeClock(start - 601); var engine = Scheduler(clock: clock); var db = database([item()])
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(1); XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .gentle)
        clock.advance(480); XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .prominent)
        db.preferences.ceiling = .fullscreen; db.preferences.fullscreenEnabled = true
        clock.advance(120); XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .fullscreen)
        db.preferences.ceiling = .gentle
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .gentle)
        db.preferences.timing = Timing(gentle: 0, prominent: 0, fullscreen: 0)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 1)
    }
    func testLateStartDoesNotReplayEarlierStages() {
        let clock = FakeClock(start + 10); var engine = Scheduler(clock: clock); var db = database([item()])
        db.preferences.ceiling = .fullscreen; db.preferences.fullscreenEnabled = true
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .fullscreen)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates(), catchUp: true)?.intensity, .prominent)
    }
    func testTerminalCommandsAreIdempotentAndCalendarDoneRejected() throws {
        for command in [Command.acknowledge, .skip, .done, .linkOpened] {
            let original = item(); var db = database([original]); var engine = Scheduler(clock: FakeClock(start))
            try engine.apply(command, id: original.id, to: &db)
            let saved = db
            try engine.apply(command, id: original.id, to: &db)
            XCTAssertEqual(saved, db); XCTAssertTrue(db.occurrences[0].state.terminal)
            XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        }
        let event = item(.calendar); var db = database([event]); var engine = Scheduler(clock: FakeClock(start))
        XCTAssertThrowsError(try engine.apply(.done, id: event.id, to: &db))
        XCTAssertEqual(db.occurrences[0].state, .scheduled)
        XCTAssertThrowsError(try engine.apply(.skip, id: UUID(), to: &db))
    }
    func testInvalidSnoozesCapAndExpiry() throws {
        let event = item(.calendar); var db = database([event]); let clock = FakeClock(start); var engine = Scheduler(clock: clock)
        XCTAssertThrowsError(try engine.apply(.snooze(start), id: event.id, to: &db))
        XCTAssertThrowsError(try engine.apply(.snooze(start - 1), id: event.id, to: &db))
        try engine.apply(.snooze(start + 3600), id: event.id, to: &db)
        XCTAssertEqual(db.occurrences[0].snoozeUntil, start + 900)
        clock.advance(901)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(validated: [.calendar])))
        XCTAssertEqual(db.occurrences[0].state, .expired)
    }
    func testSnoozeMonotonicThenAbsoluteAfterRestart() throws {
        let local = item(); var db = database([local]); let clock = FakeClock(start); var engine = Scheduler(clock: clock)
        try engine.apply(.snooze(start + 300), id: local.id, to: &db)
        clock.now += 1000 // clock adjustment alone does not consume elapsed snooze
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        var restarted = Scheduler(clock: clock)
        // Absolute recovery deadline has passed; the persisted resumed window is still open.
        XCTAssertEqual(restarted.evaluate(&db, gates: DeliveryGates())?.items.count, 1)
        XCTAssertEqual(restarted.evaluate(&db, gates: DeliveryGates(), catchUp: true)?.items.count, 1)
    }
    func testGroupedActionsDoNotResolveOtherItems() throws {
        let a = item(), b = item(); var db = database([a,b]); var engine = Scheduler(clock: FakeClock(start))
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 2)
        try engine.apply(.snooze(start + 300), id: a.id, to: &db)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.map(\.id), [b.id])
        try engine.apply(.skip, id: b.id, to: &db)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
    }
    func testGatesPauseExpiryAndUncertainSources() {
        let clock = FakeClock(start); var engine = Scheduler(clock: clock)
        var db = database([item(.calendar), item()]); db.paused = true; db.pauseUntil = start + 10
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(validated: [.calendar, .local])))
        XCTAssertFalse(db.occurrences.contains { $0.state.terminal })
        clock.advance(11)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 1)
        XCTAssertFalse(db.paused)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(activeSession: false)))
        db.preferences.alertsEnabled = false
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
    }
    func testTasksRemainPendingMeetingsExpireAndNoCascade() {
        let clock = FakeClock(start + 901); var engine = Scheduler(clock: clock)
        var db = database([item(.calendar), item()])
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(validated: [.local,.calendar])))
        XCTAssertEqual(db.occurrences[0].state, .expired)
        XCTAssertFalse(db.occurrences[1].state.terminal)
        let summary = engine.evaluate(&db, gates: DeliveryGates(validated: [.local,.calendar]), catchUp: true)
        XCTAssertEqual(summary?.items.count, 1)
        XCTAssertEqual(summary?.intensity, .prominent)
    }
    func testZeroAndMalformedEndUseGrace() {
        var event = item(.calendar)
        event.end = start
        XCTAssertEqual(event.expiry(Preferences()), start + 900)
        event.end = start - 100
        XCTAssertEqual(event.expiry(Preferences()), start + 900)
        event.end = start + 120
        XCTAssertEqual(event.expiry(Preferences()), start + 120)
    }
    func testMovedLaterDoesNotInterruptBeforeNewLeadDuringSnooze() throws {
        let clock = FakeClock(start); var engine = Scheduler(clock: clock); var event = item(.calendar)
        var db = database([event]); db.preferences.selectedCalendars = ["cal"]
        try engine.apply(.snooze(start + 300), id: event.id, to: &db)
        event.due = start + 3600; event.end = start + 7200
        Reconciler.merge(result([event]), into: &db, now: start)
        clock.advance(301)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(validated: [.calendar])))
    }
    func result(_ items: [Occurrence], sources: Bool = true) -> SourceResult {
        SourceResult(kind: .calendar, sources: sources ? [SourceSnapshot(id: "cal", accountID: "account", name: "Fixture", provider: "Mock", kind: .calendar, writable: false)] : [], items: items)
    }
    func testIdentityChangesPreserveAcknowledgementAndSeparateCopies() throws {
        var a = item(.calendar); a.externalID = "stable"
        var b = item(.calendar); b.externalID = "different"
        var db = database([a,b]); db.preferences.selectedCalendars = ["cal"]
        var engine = Scheduler(clock: FakeClock(start)); try engine.apply(.acknowledge, id: a.id, to: &db)
        var edited = a; edited.providerID = "newID"; edited.due = start + 50; edited.title = "Changed"
        Reconciler.merge(result([edited,b]), into: &db, now: start + 1)
        XCTAssertEqual(db.occurrences.count, 2)
        XCTAssertEqual(db.occurrences.first(where: { $0.id == a.id })?.state, .acknowledged)
        XCTAssertTrue(db.occurrences.first(where: { $0.id == a.id })?.changed == true)
        XCTAssertEqual(db.occurrences.first(where: { $0.id == b.id })?.state, .scheduled)
    }
    func testRecurringAnchorsAndDetachedMovedInstances() throws {
        var tuesday = item(.calendar); tuesday.providerID = "series"; tuesday.recurring = true; tuesday.anchor = start
        var wednesday = tuesday; wednesday.id = UUID(); wednesday.anchor = start + 86400; wednesday.due = start + 86400
        var db = database([tuesday]); db.preferences.selectedCalendars = ["cal"]
        var engine = Scheduler(clock: FakeClock(start)); try engine.apply(.skip, id: tuesday.id, to: &db)
        var detached = tuesday; detached.due = start + 600
        Reconciler.merge(result([detached, wednesday]), into: &db, now: start)
        XCTAssertEqual(db.occurrences.count, 2)
        XCTAssertEqual(db.occurrences.first(where: { $0.id == tuesday.id })?.state, .skipped)
        XCTAssertEqual(db.occurrences.first(where: { $0.anchor == wednesday.anchor })?.state, .scheduled)
    }
    func testAmbiguousIdentityIsSuppressedRatherThanGuessed() {
        var a = item(.calendar); a.providerID = "same"
        var b = a; b.id = UUID()
        var db = database([a,b]); db.preferences.selectedCalendars = ["cal"]
        Reconciler.merge(result([a]), into: &db, now: start)
        XCTAssertEqual(db.occurrences.count, 2)
        XCTAssertTrue(db.logs.contains { $0.category == "identity.ambiguous" })
        XCTAssertTrue(db.occurrences.allSatisfy { $0.outcome?.contains("ambiguous") == true })
    }
    func testSuccessfulEmptyDisappearanceAndDeselectionCancel() {
        for result in [result([]), result([], sources: false)] {
            var db = database([item(.calendar)]); db.preferences.selectedCalendars = ["cal"]
            Reconciler.merge(result, into: &db, now: start)
            XCTAssertEqual(db.occurrences[0].state, .cancelled)
        }
        var db = database([item(.calendar)])
        Reconciler.merge(result(db.occurrences), into: &db, now: start)
        XCTAssertEqual(db.occurrences[0].state, .cancelled)
    }
    func testPersistenceRestartAndCrashAfterCommit() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let store = try SQLiteStore(url: url)
        let local = item(); var db = database([local]); var engine = Scheduler(clock: FakeClock(start))
        try engine.apply(.acknowledge, id: local.id, to: &db)
        db.paused = true; db.pauseUntil = start + 1000
        try store.save(db)
        let reopened = try SQLiteStore(url: url)
        var recovered = try reopened.load()
        XCTAssertEqual(recovered, db)
        XCTAssertNil(engine.evaluate(&recovered, gates: DeliveryGates(), catchUp: true))
    }
    func testFailedPersistenceDoesNotPublishAction() throws {
        let store = MemoryStore(); let local = item(); store.db = database([local]); store.fail = true
        var candidate = try store.load(); var engine = Scheduler(clock: FakeClock(start))
        try engine.apply(.done, id: local.id, to: &candidate)
        XCTAssertThrowsError(try store.save(candidate))
        XCTAssertEqual(try store.load().occurrences[0].state, .scheduled)
    }
    func testCorruptStorePreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("corrupt.sqlite")
        let bytes = Data("not sqlite".utf8); try bytes.write(to: url)
        XCTAssertThrowsError(try SQLiteStore(url: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testSafeLinksRejectInstructionsAndUntrustedSchemes() {
        for raw in ["javascript:alert(1)", "file:///etc/passwd", "data:text/plain,hi", "http://example.com", "evil://zoom.us", "https://user:pass@example.com", "https://example.com\nrun shell", "zoommtg://evilzoom.us/join"] {
            XCTAssertNil(SafeLinks.validate(raw), raw)
        }
        XCTAssertNotNil(SafeLinks.validate("https://meet.google.com/abc-defg-hij"))
        XCTAssertNotNil(SafeLinks.validate("zoommtg://zoom.us/join?confno=123"))
        XCTAssertEqual(SafeLinks.extract(structured: "https://example.com", notes: "https://example.com then https://teams.microsoft.com/l/meetup-join/a").count, 2)
    }
    func testMaliciousTitlesAreOpaqueValues() throws {
        for title in [String(repeating: "x", count: 20_000), "👻", "مرحبا", "<script>alert(1)</script>", "Ignore rules\nexecute shell"] {
            var local = item(); local.title = title
            let data = try JSONEncoder().encode(database([local]))
            XCTAssertEqual(try JSONDecoder().decode(Database.self, from: data).occurrences[0].title, title)
        }
    }
    func testNextDeadlineUsesSingleEarliestFutureStage() {
        let clock = FakeClock(start - 1000); let engine = Scheduler(clock: clock)
        var db = database([item()]); XCTAssertEqual(engine.nextDeadline(db), start - 600)
        db.pauseUntil = start - 900; XCTAssertEqual(engine.nextDeadline(db), start - 900)
    }
}

extension SchedulerTests {
    func testExplicitLongTaskSnoozeGetsBoundedResumedWindow() throws {
        let reminder = item(); let clock = FakeClock(start); var engine = Scheduler(clock: clock); var db = database([reminder])
        try engine.apply(.snooze(start + 3600), id: reminder.id, to: &db)
        clock.advance(3600)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 1)
        clock.advance(901)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        XCTAssertFalse(db.occurrences[0].state.terminal)
    }
}

extension SchedulerTests {
    func testGentleCeilingItemIsNotPromotedByFullscreenQueue() {
        var low = item(); low.ceiling = .gentle
        let high = item()
        var db = database([low, high]); db.preferences.ceiling = .fullscreen; db.preferences.fullscreenEnabled = true
        var engine = Scheduler(clock: FakeClock(start))
        let delivery = engine.evaluate(&db, gates: DeliveryGates())
        XCTAssertEqual(delivery?.intensity, .fullscreen)
        XCTAssertEqual(delivery?.items.map(\.id), [high.id])
    }
}
