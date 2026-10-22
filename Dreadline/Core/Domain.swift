import Foundation

enum SourceKind: String, Codable, CaseIterable { case local, calendar, reminders }
enum OccurrenceState: String, Codable, Sendable, CaseIterable {
    case scheduled, eligible, presenting, snoozed, acknowledged, completed, skipped, expired, cancelled
    var terminal: Bool { [.acknowledged, .completed, .skipped, .expired, .cancelled].contains(self) }
}
enum Intensity: Int, Codable, Sendable, CaseIterable, Comparable {
    case gentle, prominent, fullscreen
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String { ["Gentle", "Prominent", "Fullscreen"][rawValue] }
}
struct Timing: Codable, Sendable, Equatable {
    var gentle: Double = 600
    var prominent: Double = 120
    var fullscreen: Double = 0
    var valid: Bool { gentle >= prominent && prominent >= fullscreen && fullscreen >= 0 && gentle <= 604800 }
}
struct QuietHours: Codable, Sendable, Equatable {
    var enabled = false
    var startMinute = 22 * 60
    var endMinute = 8 * 60
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return startMinute == endMinute || (startMinute < endMinute ? (m >= startMinute && m < endMinute) : (m >= startMinute || m < endMinute))
    }
    func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        return [startMinute, endMinute].compactMap { minute in
            calendar.nextDate(after: date, matching: DateComponents(hour: minute / 60, minute: minute % 60), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        }.min()
    }
}
struct Preferences: Codable, Sendable, Equatable {
    var selectedCalendars: Set<String> = []
    var selectedLists: Set<String> = []
    var alertsEnabled = false
    var ceiling: Intensity = .prominent
    var fullscreenEnabled = false
    var timing = Timing()
    var grace: Double = 900
    var taskWindow: Double = 900
    var snoozeMinutes = 5
    var sound = false
    var volume = 0.4
    var reducedMotion = false
    var dimAllDisplays = false
    var privateTitles = false
    var quiet = QuietHours()
    var retentionDays = 30
    var fallback = false
    var includeAllDay = false
    var allDayMinute = 9 * 60
    var dateOnlyMinute = 9 * 60
    var includeFree = false
    var includeUnanswered = false
    var includeTentative = false
    var onboardingComplete = false
}
enum RepeatFrequency: String, Codable, Sendable, CaseIterable { case none, daily, weekdays, weekly, monthly }
struct Recurrence: Codable, Sendable, Equatable {
    var frequency: RepeatFrequency = .none
    var hour = 9
    var minute = 0
    var weekdays: Set<Int> = [2,3,4,5,6]
    var weekday = 2
    var day = 1
    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        guard frequency != .none else { return nil }
        // Iterate local dates, resolving gaps to the next valid time and folds to the first.
        for offset in 0...400 {
            guard let d = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
            let c = calendar.dateComponents([.weekday, .day], from: d)
            let last = calendar.range(of: .day, in: .month, for: d)?.count ?? 28
            let matches: Bool
            switch frequency {
            case .none: matches = false
            case .daily: matches = true
            case .weekdays: matches = weekdays.contains(c.weekday ?? 0)
            case .weekly: matches = c.weekday == weekday
            case .monthly: matches = c.day == min(day, last)
            }
            guard matches else { continue }
            let before = d.addingTimeInterval(-1)
            if let candidate = calendar.nextDate(after: before, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first), calendar.isDate(candidate, inSameDayAs: d), candidate > date { return candidate }
        }
        return nil
    }
}
struct LocalReminder: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var notes = ""
    var url = ""
    var due: Date
    var recurrence = Recurrence()
    var intensity: Intensity = .prominent
    var sound = false
    var snoozeMinutes = 5
}
struct Occurrence: Codable, Sendable, Identifiable, Equatable {
    var id = UUID()
    var kind: SourceKind
    var sourceID: String
    var accountID: String = ""
    var sourceName: String
    var providerID: String
    var externalID: String = ""
    var anchor: Date?
    var seriesID: UUID?
    var title: String
    var location = ""
    var links: [String] = []
    var due: Date?
    var end: Date?
    var state: OccurrenceState = .scheduled
    var snoozeUntil: Date?
    var deliveryWindowEnd: Date?
    var lastStage: Intensity?
    var timing: Timing?
    var ceiling: Intensity?
    var changed = false
    var recurring = false
    var writable = true
    var updated = Date()
    var outcome: String?
    var resolvedAt: Date?
    func expiry(_ prefs: Preferences) -> Date? {
        guard let due else { return nil }
        if kind != .calendar { return max(due.addingTimeInterval(prefs.taskWindow), deliveryWindowEnd ?? .distantPast) }
        let grace = due.addingTimeInterval(prefs.grace)
        guard let end, end > due else { return grace }
        return min(end, grace)
    }
    func firstAlert(_ prefs: Preferences) -> Date? { due?.addingTimeInterval(-(timing ?? prefs.timing).gentle) }
}
struct Diagnostic: Codable, Sendable, Equatable { var date: Date; var category: String }
struct Database: Codable, Sendable, Equatable {
    var version = 1
    var preferences = Preferences()
    var occurrences: [Occurrence] = []
    var locals: [LocalReminder] = []
    var paused = false
    var pauseUntil: Date?
    var logs: [Diagnostic] = []
    mutating func log(_ category: String, now: Date) {
        logs.append(Diagnostic(date: now, category: category))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }
}
struct SourceSnapshot: Sendable {
    var id: String
    var accountID: String
    var name: String
    var provider: String
    var kind: SourceKind
    var writable: Bool
}
extension SourceKind: Sendable {}
struct SourceResult: Sendable {
    var kind: SourceKind
    var sources: [SourceSnapshot]
    var items: [Occurrence]
}
enum DomainError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}
protocol Clock { var now: Date { get }; var uptime: TimeInterval { get } }
struct SystemClock: Clock { var now: Date { Date() }; var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime } }
protocol StateStore { func load() throws -> Database; func save(_ database: Database) throws }

// History payloads are pruned without forgetting a still-fetched occurrence's delivery state.
extension Database {
    mutating func pruneHistory(working result: SourceResult, now: Date) {
        let cutoff = now.addingTimeInterval(-Double(preferences.retentionDays) * 86400)
        occurrences.removeAll { item in
            guard item.state.terminal, (item.resolvedAt ?? item.updated) < cutoff else { return false }
            if item.kind == .local { return true }
            guard item.kind == result.kind else { return false }
            return !result.items.contains { incoming in
                incoming.sourceID == item.sourceID && incoming.providerID == item.providerID && (!(item.recurring || incoming.recurring) || incoming.anchor == item.anchor)
            }
        }
        prunePrivateHistory(now: now)
    }
}

extension Database {
    mutating func prunePrivateHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(preferences.retentionDays) * 86400)
        occurrences.removeAll { $0.kind == .local && $0.state.terminal && ($0.resolvedAt ?? $0.updated) < cutoff }
        for i in occurrences.indices where occurrences[i].state.terminal && (occurrences[i].resolvedAt ?? occurrences[i].updated) < cutoff {
            occurrences[i].title = "History details cleared"
            occurrences[i].sourceName = "Retained delivery record"
            occurrences[i].location = ""; occurrences[i].links = []
        }
    }
}
