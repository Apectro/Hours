import Foundation

/// Field allowance, kilometres and travel over a span of days, and what the
/// first two come to at the rates in settings.
///
/// Made from days the engine has already resolved, so it says what the days
/// say, and counted by the rule money is counted by
/// (`EarningsSummary.counts(_:through:)`): an excluded day, a day before the
/// balance starts and a day still to come add nothing. It needs no hourly
/// rate — someone who tracks only the allowance still sees their days and
/// kilometres — and with no rates set the amounts are simply zero.
struct AllowanceSummary: Hashable, Sendable {
    var allowanceDays = 0
    var kilometres = 0
    var travelMinutes = 0
    /// The part of `travelMinutes` already counted as worked time.
    var countedTravelMinutes = 0
    var allowanceCents = 0
    var mileageCents = 0

    init() {}

    init(days: [DayComputation], settings: AppSettings, countingThrough: CalendarDate? = nil) {
        let rates = settings.allowance
        guard rates.isEnabled else { return }
        for day in days where EarningsSummary.counts(day, through: countingThrough) {
            if day.hasFieldAllowance { allowanceDays += 1 }
            kilometres += day.kilometres
            travelMinutes += day.travelMinutes
            countedTravelMinutes += day.countedTravelMinutes
        }
        allowanceCents = allowanceDays * rates.dailyAllowanceCents
        mileageCents = kilometres * rates.centsPerKilometre
    }

    /// The allowance and the kilometres together. Travel has no amount of its
    /// own: when it counts as work it is paid as work.
    var totalCents: Int { allowanceCents + mileageCents }

    /// Nothing recorded, so there is no line to show.
    var isEmpty: Bool { allowanceDays == 0 && kilometres == 0 && travelMinutes == 0 }
}
