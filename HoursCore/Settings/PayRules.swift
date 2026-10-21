import Foundation

/// When an hour starts to pay more than the ones before it.
enum OvertimeMode: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Every hour pays the same. Not `none`, which reads as `Optional.none`
    /// wherever one of these is optional.
    case sameRate
    /// The hours beyond a normal day.
    case afterDailyHours
    /// The hours beyond the contracted week.
    case afterWeeklyHours

    var id: String { rawValue }
}

/// How one job pays.
///
/// Money is whole cents and percentages are whole percents, so nothing here
/// is a floating-point number: a month of earnings has to add up to the cent,
/// every time, on every device.
struct PayRules: Hashable, Codable, Sendable {
    /// What an hour pays before any surcharge, in cents.
    var hourlyRateCents: Int {
        didSet { hourlyRateCents = max(0, hourlyRateCents) }
    }

    var overtimeMode: OvertimeMode
    /// Added to the rate for an hour of overtime: 25 is a quarter more.
    var overtimePercent: Int {
        didSet { overtimePercent = max(0, overtimePercent) }
    }
    /// A normal day, when it is not the day the schedule expects. Nil reads
    /// the schedule in force that day, which is what most contracts mean.
    var dailyThresholdMinutes: Int?
    /// The contracted week, when it is not the schedule's. Nil reads the
    /// schedule.
    var weeklyThresholdMinutes: Int?

    var saturdayPercent: Int {
        didSet { saturdayPercent = max(0, saturdayPercent) }
    }
    /// Sundays and public holidays share one figure: contracts that pay a
    /// surcharge for one almost always pay the same for the other.
    var sundayAndHolidayPercent: Int {
        didSet { sundayAndHolidayPercent = max(0, sundayAndHolidayPercent) }
    }
    var nightPercent: Int {
        didSet { nightPercent = max(0, nightPercent) }
    }
    /// The night window. It may run across midnight, and by default does.
    var nightStart: TimeOfDay
    var nightEnd: TimeOfDay

    /// Whether a day of paid absence — leave, sick, a public holiday — earns
    /// its credited hours at the rate. On by default, because that is what
    /// "paid" means.
    var paidAbsenceEarns: Bool

    init(
        hourlyRateCents: Int = 0,
        overtimeMode: OvertimeMode = .sameRate,
        overtimePercent: Int = 0,
        dailyThresholdMinutes: Int? = nil,
        weeklyThresholdMinutes: Int? = nil,
        saturdayPercent: Int = 0,
        sundayAndHolidayPercent: Int = 0,
        nightPercent: Int = 0,
        nightStart: TimeOfDay = TimeOfDay(hour: 22, minute: 0),
        nightEnd: TimeOfDay = TimeOfDay(hour: 6, minute: 0),
        paidAbsenceEarns: Bool = true
    ) {
        self.hourlyRateCents = max(0, hourlyRateCents)
        self.overtimeMode = overtimeMode
        self.overtimePercent = max(0, overtimePercent)
        self.dailyThresholdMinutes = dailyThresholdMinutes.map { max(0, $0) }
        self.weeklyThresholdMinutes = weeklyThresholdMinutes.map { max(0, $0) }
        self.saturdayPercent = max(0, saturdayPercent)
        self.sundayAndHolidayPercent = max(0, sundayAndHolidayPercent)
        self.nightPercent = max(0, nightPercent)
        self.nightStart = nightStart
        self.nightEnd = nightEnd
        self.paidAbsenceEarns = paidAbsenceEarns
    }

    /// Whether a wall-clock minute of the day falls in the night window.
    /// A window whose start and end are the same is no window at all.
    func isNight(minuteOfDay minute: Int) -> Bool {
        let start = nightStart.minutes
        let end = nightEnd.minutes
        if start == end { return false }
        return start < end
            ? minute >= start && minute < end
            : minute >= start || minute < end
    }

    private enum CodingKeys: String, CodingKey {
        case hourlyRateCents, overtimeMode, overtimePercent, dailyThresholdMinutes, weeklyThresholdMinutes
        case saturdayPercent, sundayAndHolidayPercent, nightPercent, nightStart, nightEnd, paidAbsenceEarns
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PayRules()
        self.init(
            hourlyRateCents: container.lenient(.hourlyRateCents, defaults.hourlyRateCents),
            overtimeMode: container.lenient(.overtimeMode, defaults.overtimeMode),
            overtimePercent: container.lenient(.overtimePercent, defaults.overtimePercent),
            dailyThresholdMinutes: container.lenientOptional(.dailyThresholdMinutes, Int.self),
            weeklyThresholdMinutes: container.lenientOptional(.weeklyThresholdMinutes, Int.self),
            saturdayPercent: container.lenient(.saturdayPercent, defaults.saturdayPercent),
            sundayAndHolidayPercent: container.lenient(.sundayAndHolidayPercent, defaults.sundayAndHolidayPercent),
            nightPercent: container.lenient(.nightPercent, defaults.nightPercent),
            nightStart: container.lenient(.nightStart, defaults.nightStart),
            nightEnd: container.lenient(.nightEnd, defaults.nightEnd),
            paidAbsenceEarns: container.lenient(.paidAbsenceEarns, defaults.paidAbsenceEarns)
        )
    }
}

extension PayRules: DatedValue {
    static var versionKey: String { "rules" }
    static var initialValue: PayRules { PayRules() }
}

/// A job's pay over time, so a raise does not rewrite the months before it.
typealias PayHistory = DatedHistory<PayRules>

/// What the app leads with: what you earned, or how far ahead of your hours
/// you are.
enum MainFigure: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case earnings
    case hoursBalance

    var id: String { rawValue }
}
