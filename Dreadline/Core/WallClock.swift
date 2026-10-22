import Foundation

enum WallClock {
    static func time(on day: Date, minute: Int, calendar: Calendar = .current) -> Date? {
        guard (0..<1440).contains(minute) else { return nil }
        return calendar.nextDate(after: calendar.startOfDay(for: day).addingTimeInterval(-1), matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0), matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
    static func reminderDue(_ components: DateComponents?, dateOnlyMinute: Int, calendar: Calendar = .current) -> Date? {
        guard let components, let year = components.year, let month = components.month, let day = components.day else { return nil }
        var cal = calendar
        if components.hour != nil, let zone = components.timeZone { cal.timeZone = zone }
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let minute = components.hour.map { $0 * 60 + (components.minute ?? 0) } ?? dateOnlyMinute
        return time(on: date, minute: minute, calendar: cal)
    }
}
