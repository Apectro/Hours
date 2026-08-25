import Foundation

/// A wall-clock time of day, stored as minutes since local midnight.
///
/// Deliberately *not* a `Date`: a shift that starts "at 08:00" starts at 08:00
/// on the office wall clock regardless of DST or which time zone the phone
/// thinks it is in. See `DurationPolicy` for how that choice affects durations.
struct TimeOfDay: Hashable, Comparable, Sendable {
    /// 0...1439.
    var minutes: Int

    init(minutes: Int) {
        self.minutes = min(max(minutes, 0), TimeOfDay.minutesPerDay - 1)
    }

    init(hour: Int, minute: Int) {
        self.init(minutes: hour * 60 + minute)
    }

    static let minutesPerDay = 1440

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    static let midnight = TimeOfDay(minutes: 0)

    /// Rounds to the nearest `step` minutes, used by the time pickers.
    func rounded(toNearest step: Int) -> TimeOfDay {
        guard step > 1 else { return self }
        let rounded = ((minutes + step / 2) / step) * step
        return TimeOfDay(minutes: min(rounded, TimeOfDay.minutesPerDay - 1))
    }

    /// A `Date` for this wall-clock time on `date`, in the given calendar.
    ///
    /// Returns `nil` when the time does not exist — the hour skipped by a
    /// spring-forward transition. Callers decide how to degrade.
    func date(on date: CalendarDate, in calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = date.year
        parts.month = date.month
        parts.day = date.day
        parts.hour = hour
        parts.minute = minute
        guard let resolved = calendar.date(from: parts) else { return nil }
        // `Calendar` silently shifts non-existent times forward; detect that so
        // the caller knows the wall-clock time was not real.
        let check = calendar.dateComponents([.hour, .minute], from: resolved)
        guard check.hour == hour, check.minute == minute else { return nil }
        return resolved
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }
}

extension TimeOfDay: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(minutes: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutes)
    }
}

extension TimeOfDay: CustomStringConvertible {
    /// 24-hour, zero padded. Diagnostics only — user-facing times go through
    /// `TimeFormatting`, which honours the locale and the 12/24h preference.
    var description: String { String(format: "%02d:%02d", hour, minute) }
}
