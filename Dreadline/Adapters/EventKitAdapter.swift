import Foundation
import EventKit

@MainActor
protocol SourceAdapter {
    func fetch(kind: SourceKind, preferences: Preferences, now: Date) async throws -> SourceResult
    func status(_ kind: SourceKind) -> EKAuthorizationStatus
    func request(_ kind: SourceKind) async throws -> Bool
    func complete(_ item: Occurrence) throws
}
@MainActor
final class EventKitAdapter: SourceAdapter {
    private let store = EKEventStore()
    func status(_ kind: SourceKind) -> EKAuthorizationStatus { EKEventStore.authorizationStatus(for: kind == .calendar ? .event : .reminder) }
    func request(_ kind: SourceKind) async throws -> Bool {
        if status(kind) != .notDetermined { return status(kind) == .fullAccess }
        let granted = try await (kind == .calendar ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders())
        if granted { store.reset() }
        return granted
    }
    func fetch(kind: SourceKind, preferences p: Preferences, now: Date) async throws -> SourceResult {
        guard status(kind) == .fullAccess else { throw DomainError.invalid("\(kind == .calendar ? "Calendar" : "Reminders") permission unavailable. Local reminders still work. Connect in Settings or review System Settings → Privacy & Security.") }
        let store = self.store
        let calendars = store.calendars(for: kind == .calendar ? .event : .reminder)
        let sources = calendars.map { SourceSnapshot(id: $0.calendarIdentifier, accountID: $0.source.sourceIdentifier, name: $0.title, provider: $0.source.title, kind: kind, writable: $0.allowsContentModifications) }
        let selected = kind == .calendar ? p.selectedCalendars : p.selectedLists
        let enabled = calendars.filter { selected.contains($0.calendarIdentifier) }
        guard !enabled.isEmpty else { return SourceResult(kind: kind, sources: sources, items: []) }
        var items: [Occurrence] = []
        if kind == .calendar {
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86400), end: now.addingTimeInterval(30 * 86400), calendars: enabled)
            let events = store.events(matching: predicate)
            // EventKit's calendar fetch has no NSError channel. Authorization is rechecked;
            // provider sync failures cannot be inferred from an otherwise successful empty array.
            guard status(kind) == .fullAccess else { throw DomainError.invalid("Calendar access changed during refresh.") }
            for event in events {
                guard event.status != .canceled, let start = event.startDate, start.timeIntervalSinceReferenceDate.isFinite else { continue }
                if event.isAllDay && !p.includeAllDay { continue }
                if event.availability == .free && !p.includeFree { continue }
                if let me = event.attendees?.first(where: { $0.isCurrentUser }) {
                    if me.participantStatus == .declined { continue }
                    if me.participantStatus == .pending && !p.includeUnanswered { continue }
                    if me.participantStatus == .tentative && !p.includeTentative { continue }
                }
                var due = start
                if event.isAllDay {
                    let cal = Calendar.current
                    due = WallClock.time(on: start, minute: p.allDayMinute, calendar: cal) ?? start
                }
                guard let calendar = event.calendar else { continue }
                let links = SafeLinks.extract(structured: event.url?.absoluteString, notes: event.notes)
                items.append(Occurrence(kind: .calendar, sourceID: calendar.calendarIdentifier,
                    accountID: calendar.source.sourceIdentifier, sourceName: "\(calendar.source.title) · \(calendar.title)",
                    providerID: event.calendarItemIdentifier, externalID: event.calendarItemExternalIdentifier ?? "",
                    anchor: event.occurrenceDate ?? start, title: Self.normalized(event.title), location: event.location ?? "",
                    links: links.map(\.absoluteString), due: due, end: event.endDate,
                    recurring: event.hasRecurrenceRules || event.isDetached, writable: false))
            }
        } else {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: enabled)
            let snapshots: [Occurrence] = try await withCheckedThrowingContinuation { continuation in
                // EventKit calls back on a background queue; @Sendable keeps the closure off the main actor.
                store.fetchReminders(matching: predicate) { @Sendable reminders in
                    guard let reminders else {
                        continuation.resume(throwing: DomainError.invalid("Reminders refresh failed. Existing state preserved; delivery suspended until retry."))
                        return
                    }
                    let snapshots = reminders.filter { !$0.isCompleted }.compactMap { Self.snapshot($0, preferences: p) }
                    continuation.resume(returning: snapshots)
                }
            }
            guard status(kind) == .fullAccess else { throw DomainError.invalid("Reminders access changed during refresh.") }
            items += snapshots
        }
        return SourceResult(kind: kind, sources: sources, items: items)
    }
    nonisolated private static func snapshot(_ reminder: EKReminder, preferences p: Preferences) -> Occurrence? {
                guard let calendar = reminder.calendar else { return nil }
                let due = WallClock.reminderDue(reminder.dueDateComponents, dateOnlyMinute: p.dateOnlyMinute)
                return Occurrence(kind: .reminders, sourceID: calendar.calendarIdentifier,
                    accountID: calendar.source.sourceIdentifier, sourceName: "\(calendar.source.title) · \(calendar.title)",
                    providerID: reminder.calendarItemIdentifier, externalID: reminder.calendarItemExternalIdentifier ?? "",
                    anchor: due, title: normalized(reminder.title),
                    links: SafeLinks.extract(structured: reminder.url?.absoluteString, notes: reminder.notes).map(\.absoluteString), due: due,
                    recurring: reminder.hasRecurrenceRules, writable: calendar.allowsContentModifications)
    }
    func complete(_ item: Occurrence) throws {
        guard item.kind == .reminders, status(.reminders) == .fullAccess,
              let reminder = store.calendarItem(withIdentifier: item.providerID) as? EKReminder,
              let calendar = reminder.calendar,
              calendar.calendarIdentifier == item.sourceID,
              calendar.allowsContentModifications else { throw DomainError.invalid("Source reminder is unavailable or read-only. Retry refresh or acknowledge locally.") }
        guard !reminder.hasRecurrenceRules else { throw DomainError.invalid("Recurring Apple Reminders completion is disabled: provider recurrence behavior has not been manually verified. Use Acknowledge locally or complete it in Reminders.") }
        if reminder.isCompleted { return }
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true) }
        catch { throw DomainError.invalid("Apple Reminders could not save completion. Reminder remains pending; retry or acknowledge locally.") }
    }
    nonisolated private static func normalized(_ title: String?) -> String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Untitled commitment" }
        return title
    }
}
