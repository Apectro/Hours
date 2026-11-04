import Foundation

/// The Today calendar's eighth column: one total per row of a month grid
/// (or the one row of a week), the hours of that row's whole week.
///
/// A row is a calendar week from the calendar's first weekday, all seven
/// days of it, even where the grid hides the weekend or the row runs into
/// the month before or after: a week's hours do not stop at the end of a
/// month. The figure is the period summary's paid hours (worked plus
/// credited) over that week, counted by the same rule
/// (`DayComputation.counts(through:)`), so the column can never disagree
/// with a week's totals elsewhere.
enum CalendarWeekTotals {
    /// The layout's days, a week to a row, as the grid draws them.
    static func rows(of layout: MonthLayout) -> [[CalendarDate]] {
        let width = max(layout.columnCount, 1)
        return stride(from: 0, to: layout.days.count, by: width).map {
            Array(layout.days[$0..<min($0 + width, layout.days.count)])
        }
    }

    /// Each row's whole week, in row order.
    static func weeks(of layout: MonthLayout, calendar: Calendar) -> [CalendarDateRange] {
        rows(of: layout).compactMap { row in
            row.first.map { CalendarDateRange.week(containing: $0, in: calendar) }
        }
    }

    /// Every day the totals need: the first row's week start to the last
    /// row's week end, hidden weekend days included.
    static func span(of layout: MonthLayout, calendar: Calendar) -> CalendarDateRange {
        let weeks = weeks(of: layout, calendar: calendar)
        guard let first = weeks.first, let last = weeks.last else { return layout.coveredRange }
        return CalendarDateRange(start: first.start, end: last.end)
    }

    /// Minutes worked plus credited in each row's week, in row order.
    ///
    /// - Parameters:
    ///   - days: the engine's days; any that are missing add nothing.
    ///   - countingThrough: normally today. Days after it count only what
    ///     was written on them, as in `PeriodAggregator`.
    static func minutes(
        of layout: MonthLayout,
        days: [DayComputation],
        calendar: Calendar,
        countingThrough: CalendarDate?
    ) -> [Int] {
        var byKey: [Int: DayComputation] = [:]
        byKey.reserveCapacity(days.count)
        for day in days { byKey[day.date.key] = day }

        return weeks(of: layout, calendar: calendar).map { week in
            week.days(in: calendar).reduce(0) { total, date in
                guard let day = byKey[date.key], day.counts(through: countingThrough) else { return total }
                return total + day.paidMinutes
            }
        }
    }
}
