import Foundation

/// A calendar day, independent of any time zone.
///
/// Work data is anchored to *the day the user was at work*, never to an absolute
/// instant. Storing `2026-08-04` rather than a `Date` means a trip across time
/// zones, a DST transition, or a device clock change can never move an entry
/// into a neighbouring day.
///
/// The persisted representation is the integer `key` (`yyyyMMdd`), which is
/// sortable, comparable and stable across schema migrations.
struct CalendarDate: Hashable, Comparable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Builds a date from its `yyyyMMdd` key. Returns `nil` for structurally
    /// impossible keys so corrupt storage degrades to "missing" instead of
    /// crashing.
    init?(key: Int) {
        guard key >= 1_00_01 else { return nil }
        let year = key / 10_000
        let month = (key / 100) % 100
        let day = key % 100
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func today(in calendar: Calendar, now: Date = Date()) -> CalendarDate {
        CalendarDate(now, calendar: calendar)
    }

    /// `yyyyMMdd`, e.g. `20260804`.
    var key: Int { year * 10_000 + month * 100 + day }

    var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    var components: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// A representative instant for the day.
    ///
    /// Noon is deliberate: on DST transition days midnight may not exist, and
    /// noon is never within a transition window in any real-world time zone.
    func date(in calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// 1 = Sunday ... 7 = Saturday, matching `Calendar.component(.weekday:)`.
    func weekday(in calendar: Calendar) -> Int {
        calendar.component(.weekday, from: date(in: calendar))
    }

    func adding(days: Int, in calendar: Calendar) -> CalendarDate {
        let base = date(in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return CalendarDate(moved, calendar: calendar)
    }

    /// Whole days from `self` to `other`; negative when `other` is earlier.
    func days(until other: CalendarDate, in calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: date(in: calendar))
        let to = calendar.startOfDay(for: other.date(in: calendar))
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool { lhs.key < rhs.key }
}

extension CalendarDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(Int.self)
        guard let value = CalendarDate(key: key) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid calendar date key \(key)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

extension CalendarDate: CustomStringConvertible {
    /// ISO-8601 (`2026-08-04`). Used for logs, backups and stable identifiers —
    /// never for anything the user reads, which is always locale formatted.
    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
