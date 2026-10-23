import XCTest
import Foundation

final class HauntingTests: XCTestCase {
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture(_ offset: Double = -300) -> (Database, FakeClock) {
        var db = Database(); db.preferences.alertsEnabled = true
        db.occurrences = [Occurrence(kind: .local, sourceID: "local", sourceName: "Fixture", providerID: "a", title: "Meeting", due: due)]
        return (db, FakeClock(due + offset))
    }
    func testPreludeDoesNotReplayOnRefreshAndDurablySurvivesRestart() throws {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.phase, .prelude)
        XCTAssertEqual(engine.nextDeadline(db), clock.now + Haunt.preludeSeconds)
        clock.advance(2)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.phase, .prelude)
        clock.advance(4)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        db = try JSONDecoder().decode(Database.self, from: JSONEncoder().encode(db))
        engine = Scheduler(clock: clock)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(296)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .fullscreen)
    }
    func testWakeSuppressesMissedPreludeAndArrivalJump() {
        var (db, clock) = fixture(-60); var engine = Scheduler(clock: clock)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(), catchUp: true))
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(80)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates(), catchUp: true)?.intensity, .prominent)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .prominent)
    }
    func testOverlappingMeetingsShareOnePreludeAndOneArrival() {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        var second = db.occurrences[0]; second.id = UUID(); db.occurrences.append(second)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 2)
        clock.advance(300)
        let result = engine.evaluate(&db, gates: DeliveryGates())
        XCTAssertEqual(result?.intensity, .fullscreen); XCTAssertEqual(result?.items.count, 2)
    }
    func testMeetingArrivalTakesPriorityOverAnotherPrelude() {
        var (db, clock) = fixture(0); var engine = Scheduler(clock: clock)
        var later = db.occurrences[0]; later.id = UUID(); later.due = due + 300; db.occurrences.append(later)
        let result = engine.evaluate(&db, gates: DeliveryGates())
        XCTAssertEqual(result?.phase, .reminder); XCTAssertEqual(result?.items.count, 1)
    }
    func testCancelAndRescheduleClearOldTiming() {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        _ = engine.evaluate(&db, gates: DeliveryGates())
        db.occurrences[0].due = due + 600
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(600)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.phase, .prelude)
        db.occurrences[0].state = .cancelled
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
    }
    func testSnoozeAfterArrivalDoesNotRepeatEntrance() throws {
        var (db, clock) = fixture(0); var engine = Scheduler(clock: clock)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .fullscreen)
        try engine.apply(.snooze(clock.now + 300), id: db.occurrences[0].id, to: &db)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(300)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .prominent)
    }
    func testOldPreferencesDecodeWithoutEnablingNewEffect() throws {
        let encoded = try JSONEncoder().encode(Preferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "poltergeistEnabled")
        let old = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.poltergeistEnabled)
    }
    func testPauseEndsPreludeWithoutResolvingMeeting() {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        XCTAssertNotNil(engine.evaluate(&db, gates: DeliveryGates()))
        db.paused = true
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        XCTAssertFalse(db.occurrences[0].state.terminal)
    }
}

extension HauntingTests {
    func testRefreshDuringArrivalCannotReplayEntrance() {
        var (db, clock) = fixture(0); var engine = Scheduler(clock: clock)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .fullscreen)
        clock.advance(1)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates(), catchUp: true)?.intensity, .prominent)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .prominent)
    }
    func testStaggeredPreludesDoNotExtendWorkspaceCover() {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        var later = db.occurrences[0]; later.id = UUID(); later.due = due + 1; db.occurrences.append(later)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 1)
        clock.advance(1)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.items.count, 2)
        clock.advance(5)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
    }
    func testShortSnoozeAlsoAvoidsRepeatedEntrance() throws {
        var (db, clock) = fixture(0); var engine = Scheduler(clock: clock)
        _ = engine.evaluate(&db, gates: DeliveryGates())
        try engine.apply(.snooze(clock.now + 3), id: db.occurrences[0].id, to: &db)
        clock.advance(3)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.intensity, .prominent)
    }
    func testMeetingScareStartsFiveSecondsBeforeTheMeeting() {
        var (db, clock) = fixture(); var engine = Scheduler(clock: clock)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.phase, .prelude)
        clock.advance(294)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        XCTAssertEqual(engine.nextDeadline(db), due - Haunt.arrivalLead)
        clock.advance(1)
        let arrival = engine.evaluate(&db, gates: DeliveryGates())
        XCTAssertEqual(arrival?.intensity, .fullscreen)
        XCTAssertEqual(arrival?.phase, .reminder)
    }
    func testDashRunsOnceTenSecondsBeforeTheEarlyWarning() {
        var (db, clock) = fixture(-311); var engine = Scheduler(clock: clock)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        XCTAssertEqual(engine.nextDeadline(db), due - 300 - Haunt.dashLead)
        clock.advance(1)
        let dash = engine.evaluate(&db, gates: DeliveryGates())
        XCTAssertEqual(dash?.phase, .dash)
        XCTAssertEqual(db.occurrences[0].state, .scheduled, "The dash does not start the reminder")
        clock.advance(Haunt.dashSeconds)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        clock.advance(5)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()), "The dash never replays")
        clock.advance(3)
        XCTAssertEqual(engine.evaluate(&db, gates: DeliveryGates())?.phase, .prelude, "Then the early warning")
    }
    func testDashIsSkippedOnWakeAndWhilePaused() {
        var (db, clock) = fixture(-305); var engine = Scheduler(clock: clock)
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates(), catchUp: true))
        XCTAssertNil(engine.evaluate(&db, gates: DeliveryGates()))
        var (paused, pausedClock) = fixture(-305); var pausedEngine = Scheduler(clock: pausedClock)
        paused.paused = true
        XCTAssertNil(pausedEngine.evaluate(&paused, gates: DeliveryGates()))
        paused.paused = false
        XCTAssertNil(pausedEngine.evaluate(&paused, gates: DeliveryGates()), "A dash missed while paused is not replayed")
        _ = pausedClock
    }
    func testScareLevelsMapToTheirOwnSoundInTestsToo() {
        XCTAssertEqual(HauntSounds.scare(.low), .shatter)
        XCTAssertEqual(HauntSounds.scare(.medium), .scream)
        XCTAssertEqual(HauntSounds.scare(.high), .deep)
        XCTAssertTrue(HauntSounds.previews(.high).contains { $0.sound == .deep }, "Tests play the real High scare")
        XCTAssertFalse([HauntSounds.earlyWarning, HauntSounds.snooze, HauntSounds.dismiss, HauntSounds.sideReminder].contains(.deep),
                       "Only the High meeting scare uses it")
    }
    func testOlderPreferencesDefaultToMediumScare() throws {
        let encoded = try JSONEncoder().encode(Preferences())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "scareLevel")
        let old = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.scareLevel)
        XCTAssertEqual(HauntSounds.scare(old.scareLevel ?? .medium), .scream)
    }
    func testEveryHauntSoundIsBundled() {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Dreadline/Resources")
        for sound in HauntSound.allCases {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appendingPathComponent(sound.rawValue + ".m4a").path), sound.rawValue)
        }
    }
    func testEveryHauntingArtworkIsBundled() {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Dreadline/Resources")
        for name in ["ghost-grin", "ghost-scream", "ghost-standing", "ghost-hanging", "ghost-crawling", "ghost-dash"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appendingPathComponent(name + ".webp").path), name)
        }
    }
}
