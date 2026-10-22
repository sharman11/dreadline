import XCTest
import Foundation

final class RecurrenceTests: XCTestCase {
    func calendar(_ zone: String = "America/New_York") -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testMonthlyClampLeapDayAndTravel() {
        let c = calendar("UTC")
        let rule = Recurrence(frequency: .monthly, hour: 9, minute: 0, day: 31)
        XCTAssertEqual(rule.next(after: date("2024-02-01T00:00:00Z"), calendar: c), date("2024-02-29T09:00:00Z"))
        XCTAssertEqual(rule.next(after: date("2025-02-01T00:00:00Z"), calendar: c), date("2025-02-28T09:00:00Z"))
        XCTAssertEqual(rule.next(after: date("2025-04-01T00:00:00Z"), calendar: c), date("2025-04-30T09:00:00Z"))
        let daily = Recurrence(frequency: .daily, hour: 9)
        let now = date("2026-10-22T00:00:00Z")
        XCTAssertNotEqual(daily.next(after: now, calendar: c), daily.next(after: now, calendar: calendar("Asia/Kolkata")))
    }
    func testDSTGapUsesNextValidTimeAndFoldFirstOnly() {
        let c = calendar()
        let gap = Recurrence(frequency: .daily, hour: 2, minute: 30)
        let next = gap.next(after: date("2026-03-08T05:00:00Z"), calendar: c)!
        XCTAssertEqual(next, date("2026-03-08T07:00:00Z"))
        let fold = Recurrence(frequency: .daily, hour: 1, minute: 30)
        let first = fold.next(after: date("2026-11-01T04:00:00Z"), calendar: c)!
        XCTAssertEqual(first, date("2026-11-01T05:30:00Z"))
        XCTAssertEqual(fold.next(after: first, calendar: c), date("2026-11-02T06:30:00Z"))
    }
    func testWeeklyAndSelectedWeekdays() {
        let c = calendar("UTC"), now = date("2026-10-22T00:00:00Z") // Thursday
        let weekly = Recurrence(frequency: .weekly, hour: 9, weekday: 2)
        XCTAssertEqual(weekly.next(after: now, calendar: c), date("2026-10-26T09:00:00Z"))
        let selected = Recurrence(frequency: .weekdays, hour: 9, weekdays: [6])
        XCTAssertEqual(selected.next(after: now, calendar: c), date("2026-10-23T09:00:00Z"))
        XCTAssertNil(Recurrence(frequency: .none).next(after: now, calendar: c))
    }
    func testQuietHoursOvernightDSTAndAllDay() {
        let c = calendar("UTC")
        var q = QuietHours(enabled: true, startMinute: 22 * 60, endMinute: 8 * 60)
        XCTAssertTrue(q.contains(date("2026-10-22T23:00:00Z"), calendar: c))
        XCTAssertTrue(q.contains(date("2026-10-23T07:59:00Z"), calendar: c))
        XCTAssertFalse(q.contains(date("2026-10-23T08:00:00Z"), calendar: c))
        XCTAssertEqual(q.nextBoundary(after: date("2026-10-22T23:00:00Z"), calendar: c), date("2026-10-23T08:00:00Z"))
        q.startMinute = q.endMinute
        XCTAssertTrue(q.contains(date("2026-10-23T12:00:00Z"), calendar: c))
        q.enabled = false
        XCTAssertFalse(q.contains(Date()))
    }
    func testLocalRecurringCompletionOnlySchedulesOneNext() throws {
        let now = date("2026-10-22T09:00:00Z")
        let clock = FakeClock(now)
        let local = LocalReminder(title: "Daily", due: now, recurrence: Recurrence(frequency: .daily, hour: 9))
        let item = Scheduler.occurrence(local)
        var db = Database(); db.locals = [local]; db.occurrences = [item]
        var scheduler = Scheduler(clock: clock)
        try scheduler.apply(.done, id: item.id, to: &db)
        XCTAssertEqual(db.occurrences.count, 2)
        XCTAssertEqual(db.locals.count, 1)
        XCTAssertEqual(db.occurrences[0].state, .completed)
        XCTAssertEqual(db.occurrences[1].seriesID, local.id)
        XCTAssertGreaterThan(db.occurrences[1].due!, now)
        try scheduler.apply(.done, id: item.id, to: &db)
        XCTAssertEqual(db.occurrences.count, 2)
    }
}

extension RecurrenceTests {
    func testRetainedDeliveryRecordDoesNotResurrectAfterHistoryRetention() {
        let now = date("2026-10-22T09:00:00Z")
        var item = Occurrence(kind: .reminders, sourceID: "c", sourceName: "Private list", providerID: "p", title: "Sensitive title", links: ["https://private.example.com"], state: .acknowledged, resolvedAt: now - 40 * 86400)
        var db = Database(); db.preferences.selectedLists = ["c"]; db.occurrences = [item]
        let snapshot = SourceResult(kind: .reminders, sources: [SourceSnapshot(id: "c", accountID: "", name: "Mock", provider: "Fake", kind: .reminders, writable: true)], items: [item])
        db.pruneHistory(working: snapshot, now: now)
        XCTAssertEqual(db.occurrences.count, 1)
        XCTAssertEqual(db.occurrences[0].title, "History details cleared")
        XCTAssertTrue(db.occurrences[0].links.isEmpty)
        item.state = .scheduled; item.resolvedAt = nil
        var refetch = snapshot; refetch.items = [item]
        Reconciler.merge(refetch, into: &db, now: now)
        XCTAssertEqual(db.occurrences[0].state, .acknowledged)
        db.pruneHistory(working: SourceResult(kind: .reminders, sources: snapshot.sources, items: []), now: now)
        XCTAssertTrue(db.occurrences.isEmpty)
    }
}

extension RecurrenceTests {
    func testDateOnlyUndatedTimedAndAllDayUseLocalWallClock() {
        let c = calendar("Asia/Kolkata")
        let components = DateComponents(year: 2026, month: 10, day: 22)
        XCTAssertEqual(WallClock.reminderDue(components, dateOnlyMinute: 540, calendar: c), date("2026-10-22T03:30:00Z"))
        XCTAssertNil(WallClock.reminderDue(nil, dateOnlyMinute: 540, calendar: c))
        var timed = components; timed.hour = 9; timed.minute = 0; timed.timeZone = TimeZone(identifier: "UTC")
        XCTAssertEqual(WallClock.reminderDue(timed, dateOnlyMinute: 540, calendar: c), date("2026-10-22T09:00:00Z"))
        XCTAssertEqual(WallClock.time(on: date("2026-10-22T00:00:00Z"), minute: 540, calendar: c), date("2026-10-22T03:30:00Z"))
        XCTAssertNil(WallClock.time(on: Date(), minute: -1))
    }
}
