import Foundation

/// Totals for a span of days. Every number here is derived from
/// `DayComputation` values, so a summary can never disagree with the days it
/// summarises.
struct PeriodSummary: Hashable, Sendable {
    var range: CalendarDateRange

    var workedMinutes: Int
    var creditedMinutes: Int
    var expectedMinutes: Int
    var breakMinutes: Int
    var adjustmentMinutes: Int

    /// Net of the period: the sum of daily balances.
    var balanceMinutes: Int
    /// Gross overtime: the positive days only.
    var overtimeMinutes: Int
    /// Gross shortfall: the negative days only, expressed positively.
    var deficitMinutes: Int

    var daysWithEntries: Int
    var scheduledWorkingDays: Int
    var daysWorked: Int
    var daysOff: Int
    var paidAbsenceDays: Int
    var countsByType: [DayTypeID: Int]

    /// Hours paid: worked plus credited absence.
    var paidMinutes: Int { workedMinutes + creditedMinutes }

    /// Average over the days actually worked — the figure people mean by
    /// "average day". Zero when nothing was worked.
    var averageWorkedMinutesPerWorkedDay: Int {
        daysWorked > 0 ? workedMinutes / daysWorked : 0
    }

    /// Average over every scheduled working day, including days off sick or on
    /// leave. Lower than the above, and the right figure for capacity.
    var averageWorkedMinutesPerScheduledDay: Int {
        scheduledWorkingDays > 0 ? workedMinutes / scheduledWorkingDays : 0
    }

    func count(of type: DayTypeID) -> Int { countsByType[type] ?? 0 }

    var isEmpty: Bool {
        workedMinutes == 0 && creditedMinutes == 0 && expectedMinutes == 0 && daysWithEntries == 0
    }

    static func empty(range: CalendarDateRange) -> PeriodSummary {
        PeriodSummary(
            range: range,
            workedMinutes: 0,
            creditedMinutes: 0,
            expectedMinutes: 0,
            breakMinutes: 0,
            adjustmentMinutes: 0,
            balanceMinutes: 0,
            overtimeMinutes: 0,
            deficitMinutes: 0,
            daysWithEntries: 0,
            scheduledWorkingDays: 0,
            daysWorked: 0,
            daysOff: 0,
            paidAbsenceDays: 0,
            countsByType: [:]
        )
    }
}

/// Rolls days up into a summary. Excluded days contribute nothing at all —
/// not to totals, not to counts, not to averages.
enum PeriodAggregator {
    static func summarize(_ days: [DayComputation], range: CalendarDateRange) -> PeriodSummary {
        var summary = PeriodSummary.empty(range: range)

        for day in days where day.isIncluded {
            summary.workedMinutes += day.workedMinutes
            summary.creditedMinutes += day.creditedMinutes
            summary.expectedMinutes += day.expectedMinutes
            summary.breakMinutes += day.breakMinutes
            summary.adjustmentMinutes += day.adjustmentMinutes
            summary.balanceMinutes += day.balanceMinutes
            summary.overtimeMinutes += day.overtimeMinutes
            summary.deficitMinutes += day.deficitMinutes

            if day.hasEntry { summary.daysWithEntries += 1 }
            if day.isScheduledWorkingDay { summary.scheduledWorkingDays += 1 }
            if day.workedMinutes > 0 { summary.daysWorked += 1 }
            if day.dayType.expectation == .zero { summary.daysOff += 1 }
            if day.dayType.expectation == .creditedAbsence { summary.paidAbsenceDays += 1 }

            summary.countsByType[day.dayType.id, default: 0] += 1
        }

        return summary
    }
}
