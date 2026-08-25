import Foundation

/// The shape of a month grid: which days go in which cells, and which columns
/// are shown. Pure layout arithmetic, kept out of the view so it can be tested
/// against awkward months (a February starting on the first column, a 31-day
/// month needing six rows, leap years).
struct MonthLayout: Hashable, Sendable {
    var month: YearMonth
    /// Every cell in reading order, including the leading and trailing days
    /// borrowed from the neighbouring months.
    var days: [CalendarDate]
    /// Weekday numbers (1 = Sunday) in display order, weekends removed if the
    /// user hides them.
    var weekdays: [Int]
    /// A month grid dims the days it borrows from its neighbours; a week grid
    /// has no "outside", so nothing is dimmed.
    var dimsOutsideMonth: Bool = true

    var columnCount: Int { weekdays.count }
    var rowCount: Int { columnCount > 0 ? days.count / columnCount : 0 }

    func isInMonth(_ date: CalendarDate) -> Bool {
        dimsOutsideMonth ? month.contains(date) : true
    }

    static func make(
        month: YearMonth,
        calendar: Calendar,
        includesWeekends: Bool
    ) -> MonthLayout {
        let orderedWeekdays = (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
        // Saturday (7) and Sunday (1) by definition here — hiding columns is
        // about the shape of the week, not about which days are contracted.
        let visibleWeekdays = includesWeekends
            ? orderedWeekdays
            : orderedWeekdays.filter { $0 != 1 && $0 != 7 }

        let firstOfMonth = month.firstDay
        let leadingOffset = (firstOfMonth.weekday(in: calendar) - calendar.firstWeekday + 7) % 7
        let gridStart = firstOfMonth.adding(days: -leadingOffset, in: calendar)
        let cellsNeeded = leadingOffset + month.dayCount(in: calendar)
        let rows = Int((Double(cellsNeeded) / 7.0).rounded(.up))

        var days: [CalendarDate] = []
        days.reserveCapacity(rows * visibleWeekdays.count)
        for row in 0..<max(rows, 1) {
            for column in 0..<7 {
                let date = gridStart.adding(days: row * 7 + column, in: calendar)
                let weekday = date.weekday(in: calendar)
                guard visibleWeekdays.contains(weekday) else { continue }
                days.append(date)
            }
        }

        return MonthLayout(month: month, days: days, weekdays: visibleWeekdays)
    }

    /// A single week, laid out with the same column rules as a month so the
    /// two scopes render through one view.
    static func week(
        containing date: CalendarDate,
        calendar: Calendar,
        includesWeekends: Bool
    ) -> MonthLayout {
        let orderedWeekdays = (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
        let visibleWeekdays = includesWeekends
            ? orderedWeekdays
            : orderedWeekdays.filter { $0 != 1 && $0 != 7 }

        let range = CalendarDateRange.week(containing: date, in: calendar)
        let days = range.days(in: calendar).filter { visibleWeekdays.contains($0.weekday(in: calendar)) }
        return MonthLayout(
            month: date.yearMonth,
            days: days,
            weekdays: visibleWeekdays,
            dimsOutsideMonth: false
        )
    }

    /// The full span the grid touches, so a single fetch covers every visible
    /// cell including the borrowed ones.
    var coveredRange: CalendarDateRange {
        guard let first = days.first, let last = days.last else {
            return CalendarDateRange(single: month.firstDay)
        }
        return CalendarDateRange(start: first, end: last)
    }
}
