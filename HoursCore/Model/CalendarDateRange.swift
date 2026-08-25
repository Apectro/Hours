import Foundation

/// An inclusive span of calendar days. Every aggregation and export in the app
/// is expressed as one of these.
struct CalendarDateRange: Hashable, Codable, Sendable {
    var start: CalendarDate
    var end: CalendarDate

    init(start: CalendarDate, end: CalendarDate) {
        // Tolerate reversed input rather than trapping: an inverted range is a
        // UI slip, not a programming error.
        if start <= end {
            self.start = start
            self.end = end
        } else {
            self.start = end
            self.end = start
        }
    }

    init(single day: CalendarDate) {
        self.init(start: day, end: day)
    }

    func contains(_ date: CalendarDate) -> Bool {
        date >= start && date <= end
    }

    /// Every day in the range, ascending.
    func days(in calendar: Calendar) -> [CalendarDate] {
        var result: [CalendarDate] = []
        var cursor = start
        // Bounded so a pathological calendar can never spin forever.
        var guardCounter = 0
        while cursor <= end && guardCounter < 200_000 {
            result.append(cursor)
            cursor = cursor.adding(days: 1, in: calendar)
            guardCounter += 1
        }
        return result
    }

    var dayKeys: ClosedRange<Int> { start.key...end.key }
}

extension CalendarDateRange {
    static func month(_ month: YearMonth, in calendar: Calendar) -> CalendarDateRange {
        month.range(in: calendar)
    }

    static func year(_ year: Int, in calendar: Calendar) -> CalendarDateRange {
        CalendarDateRange(
            start: CalendarDate(year: year, month: 1, day: 1),
            end: CalendarDate(year: year, month: 12, day: 31)
        )
    }

    /// The week containing `date`, honouring the calendar's `firstWeekday`.
    static func week(containing date: CalendarDate, in calendar: Calendar) -> CalendarDateRange {
        let weekday = date.weekday(in: calendar)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = date.adding(days: -offset, in: calendar)
        return CalendarDateRange(start: start, end: start.adding(days: 6, in: calendar))
    }
}
