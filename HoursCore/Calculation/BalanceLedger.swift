import Foundation

/// One month's contribution to the running balance.
struct MonthlyBalancePoint: Identifiable, Hashable, Sendable {
    var month: YearMonth
    var workedMinutes: Int
    var expectedMinutes: Int
    var balanceMinutes: Int
    /// Balance from the opening figure through the end of this month.
    var cumulativeMinutes: Int

    var id: Int { month.year * 100 + month.month }
}

/// The cumulative overtime balance.
///
/// The balance is not stored anywhere: it is always recomputed from the days,
/// so editing a day in the past corrects every figure that follows it rather
/// than leaving a stale total behind. An opening balance covers the hours
/// carried in from before the app was in use.
enum BalanceLedger {
    /// Balance accumulated over `days`, starting from `openingMinutes`.
    /// Days before `startDate` are ignored — that is what makes an opening
    /// balance meaningful rather than double counted.
    static func cumulative(
        over days: [DayComputation],
        openingMinutes: Int,
        startDate: CalendarDate?,
        countingThrough: CalendarDate? = nil
    ) -> Int {
        days.reduce(openingMinutes) { total, day in
            counts(day, startDate: startDate, countingThrough: countingThrough)
                ? total + day.balanceMinutes
                : total
        }
    }

    /// Whether a day contributes to the balance at all.
    ///
    /// One copy, shared by both functions here. It was two copies of the same
    /// three conditions — a quiet invitation for the running total on the
    /// statistics screen to stop agreeing with the last point of the chart
    /// printed directly beside it, and for nobody to notice, because both
    /// numbers would look perfectly plausible on their own.
    private static func counts(
        _ day: DayComputation,
        startDate: CalendarDate?,
        countingThrough: CalendarDate?
    ) -> Bool {
        // A closed year's origin is the ledger's own rule and nothing else's:
        // a period summary is not affected by a year being closed. Where the
        // balance starts is the day's own business; see `counts(through:)`.
        if let startDate, day.date < startDate { return false }
        return day.counts(through: countingThrough)
    }

    /// Month-by-month totals with a running cumulative column, for the year
    /// chart and the yearly report.
    static func monthlySeries(
        over days: [DayComputation],
        openingMinutes: Int,
        startDate: CalendarDate?,
        countingThrough: CalendarDate? = nil
    ) -> [MonthlyBalancePoint] {
        var buckets: [YearMonth: (worked: Int, expected: Int, balance: Int)] = [:]

        for day in days where counts(day, startDate: startDate, countingThrough: countingThrough) {
            let month = day.date.yearMonth
            var bucket = buckets[month] ?? (0, 0, 0)
            bucket.worked += day.workedMinutes
            bucket.expected += day.expectedMinutes
            bucket.balance += day.balanceMinutes
            buckets[month] = bucket
        }

        var running = openingMinutes
        return buckets.keys.sorted().map { month in
            let bucket = buckets[month] ?? (0, 0, 0)
            running += bucket.balance
            return MonthlyBalancePoint(
                month: month,
                workedMinutes: bucket.worked,
                expectedMinutes: bucket.expected,
                balanceMinutes: bucket.balance,
                cumulativeMinutes: running
            )
        }
    }
}

extension PeriodEngine {
    /// The running balance at the end of `end`: where it starts, which days
    /// it counts, and what they add up to.
    ///
    /// One answer for every place that shows a running balance. There were
    /// three, each choosing its own first day: the statistics card started at
    /// the first recorded day; the export started at the balance start date
    /// and ignored a closed year, so January's running-balance column began
    /// from the uncapped total of every year before; and closing a year
    /// started four years back, so every working day before the person began
    /// using the app went into the close as a full day short.
    ///
    /// The rule is the statistics card's: the origin a closed year or an
    /// opening balance gives, counted from the engine's `balanceStart` — the
    /// start date when one is set, otherwise the first day anything was
    /// recorded. A day before then is a day the app was not in use, not a day
    /// nobody turned up, and the month and the widget leave it out the same
    /// way.
    ///
    /// - Parameter records: the stored records for a range; asked once, for
    ///   the range the balance covers, so a caller can read just that much.
    func runningBalance(
        through end: CalendarDate,
        holidays: [HolidayRule],
        countingThrough: CalendarDate?,
        records: (CalendarDateRange) -> [Int: DayRecord]
    ) -> Int {
        balance(
            through: end,
            origin: settings.balanceOrigin(for: end),
            holidays: holidays,
            countingThrough: countingThrough,
            records: records
        )
    }

    /// The balance carried into `range`: everything before its first day.
    ///
    /// Read from the origin of the range's own first day, so a range that
    /// opens a year after a close starts from what the close carried rather
    /// than from the closing balance before its cap.
    func balanceCarried(
        into range: CalendarDateRange,
        holidays: [HolidayRule],
        countingThrough: CalendarDate?,
        records: (CalendarDateRange) -> [Int: DayRecord]
    ) -> Int {
        balance(
            through: range.start.adding(days: -1, in: calendar),
            origin: settings.balanceOrigin(for: range.start),
            holidays: holidays,
            countingThrough: countingThrough,
            records: records
        )
    }

    private func balance(
        through end: CalendarDate,
        origin: (openingMinutes: Int, startDate: CalendarDate?),
        holidays: [HolidayRule],
        countingThrough: CalendarDate?,
        records: (CalendarDateRange) -> [Int: DayRecord]
    ) -> Int {
        guard let begins = balanceStart else { return origin.openingMinutes }
        // A closed year moves the origin on to the January after it; before
        // that, the balance begins where every other figure does.
        let start = origin.startDate.map { Swift.max($0, begins) } ?? begins
        guard start <= end else { return origin.openingMinutes }

        let span = CalendarDateRange(start: start, end: end)
        return BalanceLedger.cumulative(
            over: days(in: span, records: records(span), holidays: holidays),
            openingMinutes: origin.openingMinutes,
            startDate: origin.startDate,
            countingThrough: countingThrough
        )
    }
}
