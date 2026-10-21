import Foundation

/// One month's earnings, for the month-by-month list.
struct MonthEarnings: Identifiable, Hashable, Sendable {
    var month: YearMonth
    var breakdown: EarningsBreakdown

    var id: Int { month.year * 100 + month.month }
    var totalCents: Int { breakdown.totalCents }
}

/// Earnings over a span of days: every part added up, and the days and
/// months they came from. A sum of days and nothing else, so a month here is
/// exactly what its days say.
struct EarningsSummary: Hashable, Sendable {
    var range: CalendarDateRange
    /// The days that earned, in order.
    var days: [DayEarnings]
    var breakdown: EarningsBreakdown
    var months: [MonthEarnings]

    init(range: CalendarDateRange, days: [DayEarnings]) {
        self.range = range
        self.days = days
        self.breakdown = days.reduce(.zero) { $0 + $1.breakdown }

        var byMonth: [YearMonth: EarningsBreakdown] = [:]
        for day in days { byMonth[day.date.yearMonth, default: .zero] += day.breakdown }
        self.months = byMonth.keys.sorted().map { MonthEarnings(month: $0, breakdown: byMonth[$0] ?? .zero) }
    }

    var totalCents: Int { breakdown.totalCents }

    var overtimeMinutes: Int { days.reduce(0) { $0 + $1.overtimeMinutes } }
    var saturdayMinutes: Int { days.reduce(0) { $0 + $1.saturdayMinutes } }
    var sundayAndHolidayMinutes: Int { days.reduce(0) { $0 + $1.sundayAndHolidayMinutes } }
    var nightMinutes: Int { days.reduce(0) { $0 + $1.nightMinutes } }

    /// Whether a day's earnings belong in a total counted through `cutoff`.
    ///
    /// Stricter than `DayComputation.counts(through:)`, which still counts a
    /// day to come once something is recorded on it — leave booked for next
    /// week is owed hours either way. Money is not earned until the day has
    /// happened, so a day after the cutoff earns nothing yet, whatever is on it.
    static func counts(_ day: DayComputation, through cutoff: CalendarDate?) -> Bool {
        guard day.counts(through: cutoff) else { return false }
        return cutoff.map { day.date <= $0 } ?? true
    }
}
