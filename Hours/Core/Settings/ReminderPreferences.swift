import Foundation

/// When to be nudged about days with nothing recorded.
struct ReminderPreferences: Hashable, Codable, Sendable {
    var isEnabled: Bool
    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var time: TimeOfDay
    /// How far back to look for gaps.
    var lookBackDays: Int

    init(
        isEnabled: Bool = false,
        weekday: Int = 6,
        time: TimeOfDay = TimeOfDay(hour: 17, minute: 0),
        lookBackDays: Int = 14
    ) {
        self.isEnabled = isEnabled
        self.weekday = min(max(weekday, 1), 7)
        self.time = time
        self.lookBackDays = min(max(lookBackDays, 1), 90)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, weekday, time, lookBackDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReminderPreferences()
        self.init(
            isEnabled: container.lenient(.isEnabled, defaults.isEnabled),
            weekday: container.lenient(.weekday, defaults.weekday),
            time: container.lenient(.time, defaults.time),
            lookBackDays: container.lenient(.lookBackDays, defaults.lookBackDays)
        )
    }
}

/// Finds days that were meant to be worked and have nothing on them.
enum GapFinder {
    static func unrecordedWorkingDays(
        in days: [DayComputation],
        asOf today: CalendarDate
    ) -> [CalendarDate] {
        days
            .filter { $0.isUnrecordedWorkingDay(asOf: today) }
            .map(\.date)
    }

    /// The window a reminder looks back over.
    static func window(
        endingAt today: CalendarDate,
        lookBackDays: Int,
        calendar: Calendar
    ) -> CalendarDateRange {
        let start = today.adding(days: -max(1, lookBackDays), in: calendar)
        // Yesterday is the last day that can be missing: today is not over.
        let end = today.adding(days: -1, in: calendar)
        return CalendarDateRange(start: start, end: end)
    }

    /// What the notification should say. Returns nil when there is nothing to
    /// report — a reminder that fires to say "all good" is a reminder people
    /// switch off.
    static func message(for gaps: [CalendarDate], formatting: CalendarFormatting) -> String? {
        switch gaps.count {
        case 0:
            return nil
        case 1:
            return "\(formatting.mediumDate(gaps[0])) has no hours recorded."
        case 2:
            return "\(formatting.mediumDate(gaps[0])) and \(formatting.mediumDate(gaps[1])) have no hours recorded."
        default:
            return "\(gaps.count) days have no hours recorded, starting \(formatting.mediumDate(gaps[0]))."
        }
    }
}
