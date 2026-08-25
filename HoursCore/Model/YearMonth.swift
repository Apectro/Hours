import Foundation

/// A month in a year. Drives calendar paging and monthly aggregation.
struct YearMonth: Hashable, Comparable, Codable, Sendable {
    var year: Int
    var month: Int

    init(year: Int, month: Int) {
        let normalized = YearMonth.normalize(year: year, month: month)
        self.year = normalized.year
        self.month = normalized.month
    }

    init(_ date: CalendarDate) {
        self.init(year: date.year, month: date.month)
    }

    static func current(in calendar: Calendar, now: Date = Date()) -> YearMonth {
        YearMonth(CalendarDate.today(in: calendar, now: now))
    }

    private static func normalize(year: Int, month: Int) -> (year: Int, month: Int) {
        // Month is expressed as a zero-based offset so that arithmetic across
        // year boundaries stays a single modulo, in both directions.
        let zeroBased = (year * 12) + (month - 1)
        // Floor division: Swift's `/` truncates towards zero, which would put
        // month 0 of year 1 into the wrong year for negative operands.
        let normalizedYear = zeroBased >= 0 ? zeroBased / 12 : -((-zeroBased + 11) / 12)
        let normalizedMonth = zeroBased - (normalizedYear * 12) + 1
        return (normalizedYear, normalizedMonth)
    }

    func adding(months: Int) -> YearMonth {
        YearMonth(year: year, month: month + months)
    }

    var firstDay: CalendarDate { CalendarDate(year: year, month: month, day: 1) }

    /// Correct for leap years because it asks `Calendar`, never a lookup table.
    func dayCount(in calendar: Calendar) -> Int {
        let reference = firstDay.date(in: calendar)
        return calendar.range(of: .day, in: .month, for: reference)?.count ?? 30
    }

    func lastDay(in calendar: Calendar) -> CalendarDate {
        CalendarDate(year: year, month: month, day: dayCount(in: calendar))
    }

    func range(in calendar: Calendar) -> CalendarDateRange {
        CalendarDateRange(start: firstDay, end: lastDay(in: calendar))
    }

    func contains(_ date: CalendarDate) -> Bool {
        date.year == year && date.month == month
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}
