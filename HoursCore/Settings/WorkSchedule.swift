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
