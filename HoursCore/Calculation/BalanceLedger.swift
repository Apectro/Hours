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
            guard day.isIncluded else { return total }
            if let startDate, day.date < startDate { return total }
            if let countingThrough, day.date > countingThrough, !day.hasEntry { return total }
            return total + day.balanceMinutes
        }
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

        for day in days where day.isIncluded {
            if let startDate, day.date < startDate { continue }
            if let countingThrough, day.date > countingThrough, !day.hasEntry { continue }
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
