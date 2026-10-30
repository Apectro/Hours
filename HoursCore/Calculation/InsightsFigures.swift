import Foundation

/// Insights › By site (1.2): your own hours in a period, per site, from the
/// shifts a site day wrote into your calendar. Hours you typed in yourself
/// belong to no site and are left out.
enum SiteHours {
    struct Total: Hashable, Sendable {
        var siteID: UUID
        var workedMinutes: Int
    }

    /// Largest first; a tie keeps a stable order by id.
    static func totals(_ days: [DayComputation], countingThrough today: CalendarDate) -> [Total] {
        var minutes: [UUID: Int] = [:]
        for day in days where day.counts(through: today) {
            for shift in day.shifts {
                guard let site = shift.siteID, shift.workedMinutes > 0 else { continue }
                minutes[site, default: 0] += shift.workedMinutes
            }
        }
        return minutes
            .map { Total(siteID: $0.key, workedMinutes: $0.value) }
            .sorted { ($0.workedMinutes, $1.siteID.uuidString) > ($1.workedMinutes, $0.siteID.uuidString) }
    }
}

/// Insights › Running balance (1.2): the balance as a line through the
/// period, ending at the running balance itself.
///
/// Worked backwards from that figure — the one the card prints — by taking
/// off each later day's own balance, so the line and the number can never
/// disagree, whatever opening balance or carried year sits underneath.
enum BalanceTrend {
    struct Point: Hashable, Sendable {
        var date: CalendarDate
        var minutes: Int
    }

    /// - Parameters:
    ///   - days: the period's days, in date order.
    ///   - endingMinutes: the running balance at the end of the period.
    ///   - through: the last day drawn, usually today; later days still
    ///     count towards the balance but get no point.
    static func points(days: [DayComputation], endingMinutes: Int, through: CalendarDate) -> [Point] {
        let sorted = days.sorted { $0.date < $1.date }
        var after = 0
        var reversed: [Point] = []
        for day in sorted.reversed() {
            if day.date <= through {
                reversed.append(Point(date: day.date, minutes: endingMinutes - after))
            }
            if day.counts(through: through) { after += day.balanceMinutes }
        }
        return reversed.reversed()
    }
}
