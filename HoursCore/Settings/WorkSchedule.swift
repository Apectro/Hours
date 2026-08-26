import Foundation

/// The contracted working week.
///
/// Hours are stored per weekday rather than as a single "hours per day" number
/// so that a 6/6/6/6/8 week, a four-day week, or a Sunday-working schedule are
/// all first-class rather than special cases.
struct WorkSchedule: Hashable, Codable, Sendable {
    /// Contracted minutes, indexed by `Calendar` weekday minus one:
    /// index 0 = Sunday ... index 6 = Saturday. Always exactly seven entries.
    private var storedMinutesByWeekday: [Int]

    var defaultStart: TimeOfDay
    var defaultEnd: TimeOfDay
    var defaultBreakMinutes: Int

    /// Overrides the sum of the per-day values when a contract states a weekly
    /// figure that does not divide evenly across days.
    var weeklyTargetOverrideMinutes: Int?

    init(
        minutesByWeekday: [Int] = WorkSchedule.standardWeekMinutes,
        defaultStart: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
        defaultEnd: TimeOfDay = TimeOfDay(hour: 16, minute: 30),
        defaultBreakMinutes: Int = 30,
        weeklyTargetOverrideMinutes: Int? = nil
    ) {
        self.storedMinutesByWeekday = WorkSchedule.normalized(minutesByWeekday)
        self.defaultStart = defaultStart
        self.defaultEnd = defaultEnd
        self.defaultBreakMinutes = max(0, defaultBreakMinutes)
        self.weeklyTargetOverrideMinutes = weeklyTargetOverrideMinutes.map { max(0, $0) }
    }

    /// Monday–Friday, eight hours a day.
    static let standardWeekMinutes: [Int] = [0, 480, 480, 480, 480, 480, 0]

    private static func normalized(_ values: [Int]) -> [Int] {
        var result = Array(repeating: 0, count: 7)
        for index in 0..<7 where index < values.count {
            result[index] = min(max(values[index], 0), TimeOfDay.minutesPerDay)
        }
        return result
    }

    var minutesByWeekday: [Int] {
        get { storedMinutesByWeekday }
        set { storedMinutesByWeekday = WorkSchedule.normalized(newValue) }
    }

    /// `weekday` is 1 = Sunday ... 7 = Saturday.
    func contractedMinutes(forWeekday weekday: Int) -> Int {
        let index = weekday - 1
        guard index >= 0 && index < storedMinutesByWeekday.count else { return 0 }
        return storedMinutesByWeekday[index]
    }

    mutating func setContractedMinutes(_ minutes: Int, forWeekday weekday: Int) {
        let index = weekday - 1
        guard index >= 0 && index < storedMinutesByWeekday.count else { return }
        storedMinutesByWeekday[index] = min(max(minutes, 0), TimeOfDay.minutesPerDay)
    }

    func isWorkingWeekday(_ weekday: Int) -> Bool {
        contractedMinutes(forWeekday: weekday) > 0
    }

    /// What this weekday is actually expected to be, once a weekly override is
    /// taken into account.
    ///
    /// The per-day figures say how the week is shaped; a weekly override says
    /// what it has to add up to. When both are set they can disagree, and the
    /// balance used to be computed from the days while the settings screen
    /// displayed the override — so someone whose contract says 37½ hours, set
    /// as the override over days summing to 40, ran two and a half hours short
    /// every week, forever, while the app told them their target was 37½. The
    /// screen reassuring you is what makes that one nasty.
    ///
    /// The override wins, because it is the contract. The shape is kept: a
    /// short Friday stays proportionally short.
    ///
    /// Distributed through a running total rather than by scaling each day on
    /// its own. Scaling independently rounds seven times and the week lands a
    /// few minutes off its target — small, but this is a balance measured in
    /// minutes and the error repeats every week of the year. Taking the
    /// difference between two cumulative totals puts every remainder
    /// somewhere, sums to the target exactly, and still lets one day be worked
    /// out without looking at the others.
    func expectedMinutes(forWeekday weekday: Int) -> Int {
        guard let target = weeklyTargetOverrideMinutes else {
            return contractedMinutes(forWeekday: weekday)
        }
        let index = weekday - 1
        guard index >= 0, index < storedMinutesByWeekday.count else { return 0 }

        let summed = summedWeeklyMinutes
        // No shape to spread the target over. Sharing it evenly would invent
        // working days out of nothing.
        guard summed > 0 else { return 0 }

        func cumulative(throughIndex end: Int) -> Int {
            storedMinutesByWeekday.prefix(end).reduce(0, +) * target / summed
        }
        return cumulative(throughIndex: index + 1) - cumulative(throughIndex: index)
    }

    /// The contracted week, honouring an explicit override if one is set.
    var weeklyTargetMinutes: Int {
        weeklyTargetOverrideMinutes ?? storedMinutesByWeekday.reduce(0, +)
    }

    var summedWeeklyMinutes: Int { storedMinutesByWeekday.reduce(0, +) }

    var workingDaysPerWeek: Int {
        storedMinutesByWeekday.filter { $0 > 0 }.count
    }

    /// The default shift length implied by the default start/end/break, used to
    /// pre-fill a new day.
    var defaultShiftMinutes: Int {
        let raw = defaultEnd.minutes >= defaultStart.minutes
            ? defaultEnd.minutes - defaultStart.minutes
            : defaultEnd.minutes + TimeOfDay.minutesPerDay - defaultStart.minutes
        return max(0, raw - defaultBreakMinutes)
    }
}

extension WorkSchedule {
    private enum CodingKeys: String, CodingKey {
        case storedMinutesByWeekday = "minutesByWeekday"
        case defaultStart
        case defaultEnd
        case defaultBreakMinutes
        case weeklyTargetOverrideMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            minutesByWeekday: container.lenient(.storedMinutesByWeekday, WorkSchedule.standardWeekMinutes),
            defaultStart: container.lenient(.defaultStart, TimeOfDay(hour: 8, minute: 0)),
            defaultEnd: container.lenient(.defaultEnd, TimeOfDay(hour: 16, minute: 30)),
            defaultBreakMinutes: container.lenient(.defaultBreakMinutes, 30),
            weeklyTargetOverrideMinutes: container.lenientOptional(.weeklyTargetOverrideMinutes, Int.self)
        )
    }
}
