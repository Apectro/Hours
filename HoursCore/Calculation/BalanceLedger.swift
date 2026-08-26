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
        // The opening balance is the ledger's own rule and nothing else's: a
        // period summary is not affected by when someone started counting.
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
