import Foundation

/// When to be nudged about days with nothing recorded.
struct ReminderPreferences: Hashable, Codable, Sendable {
    var isEnabled: Bool
    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var time: TimeOfDay
    /// How far back to look for gaps.
    var lookBackDays: Int
    /// Evening nudge for a job-site day that is probably missing. Separate
    /// from the weekly gap reminder, so it has its own switch and time.
    var siteRemindersEnabled: Bool
    var siteReminderTime: TimeOfDay
    /// On the 1st, a note per site that last month's sheet is ready for the
    /// director. On by default: it only ever says anything to someone with a
    /// site, and handing the sheet over is what a supervisor forgets.
    var monthlySheetEnabled: Bool
    var monthlySheetTime: TimeOfDay
    /// Once a week, a note when finished extra work has not been sent to the
    /// boss yet. Off by default: not everyone with a site writes extra work.
    /// Named "unsent work" rather than "extra work" so a backup of someone
    /// without extra work still carries no `extraWork` key at all
    /// (`ExtraWorkBackupTests`).
    var unsentWorkEnabled: Bool
    /// 1 = Sunday ... 7 = Saturday; Friday by default, before the weekend.
    var unsentWorkWeekday: Int
    var unsentWorkTime: TimeOfDay

    init(
        isEnabled: Bool = false,
        weekday: Int = 6,
        time: TimeOfDay = TimeOfDay(hour: 17, minute: 0),
        lookBackDays: Int = 14,
        siteRemindersEnabled: Bool = true,
        siteReminderTime: TimeOfDay = TimeOfDay(hour: 18, minute: 0),
        monthlySheetEnabled: Bool = true,
        monthlySheetTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        unsentWorkEnabled: Bool = false,
        unsentWorkWeekday: Int = 6,
        unsentWorkTime: TimeOfDay = TimeOfDay(hour: 15, minute: 0)
    ) {
        self.isEnabled = isEnabled
        self.weekday = min(max(weekday, 1), 7)
        self.time = time
        self.lookBackDays = min(max(lookBackDays, 1), 90)
        self.siteRemindersEnabled = siteRemindersEnabled
        self.siteReminderTime = siteReminderTime
        self.monthlySheetEnabled = monthlySheetEnabled
        self.monthlySheetTime = monthlySheetTime
        self.unsentWorkEnabled = unsentWorkEnabled
        self.unsentWorkWeekday = min(max(unsentWorkWeekday, 1), 7)
        self.unsentWorkTime = unsentWorkTime
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, weekday, time, lookBackDays, siteRemindersEnabled, siteReminderTime
        case monthlySheetEnabled, monthlySheetTime
        case unsentWorkEnabled, unsentWorkWeekday, unsentWorkTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReminderPreferences()
        self.init(
            isEnabled: container.lenient(.isEnabled, defaults.isEnabled),
            weekday: container.lenient(.weekday, defaults.weekday),
            time: container.lenient(.time, defaults.time),
            lookBackDays: container.lenient(.lookBackDays, defaults.lookBackDays),
            siteRemindersEnabled: container.lenient(.siteRemindersEnabled, defaults.siteRemindersEnabled),
            siteReminderTime: container.lenient(.siteReminderTime, defaults.siteReminderTime),
            monthlySheetEnabled: container.lenient(.monthlySheetEnabled, defaults.monthlySheetEnabled),
            monthlySheetTime: container.lenient(.monthlySheetTime, defaults.monthlySheetTime),
            unsentWorkEnabled: container.lenient(.unsentWorkEnabled, defaults.unsentWorkEnabled),
            unsentWorkWeekday: container.lenient(.unsentWorkWeekday, defaults.unsentWorkWeekday),
            unsentWorkTime: container.lenient(.unsentWorkTime, defaults.unsentWorkTime)
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
}
