import Foundation

extension Calendar {
    /// Gregorian calendar in the user's time zone with English month/day names.
    public static func natkeys(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}

/// Sunday math. The week "flips" every Sunday at a set time (2:00 PM by default):
///
/// - Before the flip on a Sunday, "Last Sunday" is a week ago and "Coming Sunday" is today.
/// - At/after the flip, "Last Sunday" is today and "Coming Sunday" is next week.
///
/// The weekly auto-shift uses the same instant, so the "Last Week" sermon title
/// always pairs with the "Last Sunday" date.
public struct WeekClock: Sendable {
    public var calendar: Calendar
    public var flipHour: Int
    public var flipMinute: Int

    public init(flipHour: Int = 14, flipMinute: Int = 0, calendar: Calendar = .natkeys()) {
        self.flipHour = flipHour
        self.flipMinute = flipMinute
        self.calendar = calendar
    }

    /// The most recent Sunday flip instant at or before `now`.
    public func mostRecentFlip(atOrBefore now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday in the Gregorian calendar
        let sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let flip = flipInstant(onSunday: sunday)
        if flip <= now { return flip }
        let previousSunday = calendar.date(byAdding: .day, value: -7, to: sunday)!
        return flipInstant(onSunday: previousSunday)
    }

    /// The next Sunday flip instant strictly after `now`.
    public func nextFlip(after now: Date) -> Date {
        let recentSunday = calendar.startOfDay(for: mostRecentFlip(atOrBefore: now))
        let nextSunday = calendar.date(byAdding: .day, value: 7, to: recentSunday)!
        return flipInstant(onSunday: nextSunday)
    }

    /// Start of the "Last Sunday" day.
    public func lastSunday(now: Date) -> Date {
        calendar.startOfDay(for: mostRecentFlip(atOrBefore: now))
    }

    /// Start of the "Coming Sunday" day (always Last Sunday + 7 days).
    public func comingSunday(now: Date) -> Date {
        calendar.date(byAdding: .day, value: 7, to: lastSunday(now: now))!
    }

    public func today(now: Date) -> Date {
        calendar.startOfDay(for: now)
    }

    private func flipInstant(onSunday day: Date) -> Date {
        calendar.date(bySettingHour: flipHour, minute: flipMinute, second: 0, of: day)
            ?? calendar.date(byAdding: .hour, value: flipHour, to: day)!
    }
}

/// The three columns of the date grid.
public enum DateAnchor: String, CaseIterable, Identifiable, Sendable {
    case lastSunday
    case today
    case comingSunday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lastSunday: return "Last Sunday"
        case .today: return "Today"
        case .comingSunday: return "Coming Sunday"
        }
    }

    public func date(now: Date, clock: WeekClock) -> Date {
        switch self {
        case .lastSunday: return clock.lastSunday(now: now)
        case .today: return now // the real time, so time patterns like "h:mm a" work too
        case .comingSunday: return clock.comingSunday(now: now)
        }
    }

    /// Parses the source part of a combo field, e.g. "Last Sunday" in `{Last Sunday: MMMM d}`.
    public init?(tokenName raw: String) {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "last sunday", "previous sunday": self = .lastSunday
        case "today": self = .today
        case "coming sunday", "next sunday", "this sunday": self = .comingSunday
        default: return nil
        }
    }
}

public enum DateText {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    /// Formats `date` with a Unicode date pattern such as "MMMM d" or "MM-dd-yy".
    public static func format(_ date: Date, pattern: String, calendar: Calendar = .natkeys()) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(pattern)|\(calendar.timeZone.identifier)"
        let formatter: DateFormatter
        if let cached = cache[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            cache[key] = formatter
        }
        return formatter.string(from: date)
    }
}
