import Foundation
@testable import Hours

/// Shared fixtures.
///
/// Every test pins the calendar, locale, time zone and first weekday. Nothing
/// in the engine reads `Calendar.current`, which is what makes these results
/// reproducible on any machine in any region.
enum Fixture {
    static let zagreb = "Europe/Zagreb"

    static func calendar(timeZone identifier: String = zagreb, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        calendar.timeZone = TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// Monday to Friday, eight hours a day, 08:00–16:30 with a 30-minute break.
    static func settings(
        features: FeatureToggles = FeatureToggles(),
        schedule: WorkSchedule = WorkSchedule(),
        rounding: RoundingRule = .exact,
        durationPolicy: DurationPolicy = .wallClock,
        customDayTypes: [DayTypeDefinition] = [],
        openingBalanceMinutes: Int = 0,
        export: ExportPreferences = ExportPreferences()
    ) -> AppSettings {
        AppSettings(
            features: features,
            schedule: schedule,
            export: export,
            durationPolicy: durationPolicy,
            rounding: rounding,
            customDayTypes: customDayTypes,
            openingBalanceMinutes: openingBalanceMinutes
        )
    }

    static func calculator(
        settings: AppSettings = Fixture.settings(),
        calendar: Calendar = Fixture.calendar()
    ) -> WorkdayCalculator {
        WorkdayCalculator(settings: settings, calendar: calendar)
    }

    static func engine(
        settings: AppSettings = Fixture.settings(),
        calendar: Calendar = Fixture.calendar()
    ) -> PeriodEngine {
        PeriodEngine(settings: settings, calendar: calendar)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        CalendarDate(year: year, month: month, day: day)
    }

    static func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay {
        TimeOfDay(hour: hour, minute: minute)
    }

    /// A plain working day: Tuesday 4 August 2026.
    static let workingTuesday = CalendarDate(year: 2026, month: 8, day: 4)
    /// Monday 3 August 2026.
    static let workingMonday = CalendarDate(year: 2026, month: 8, day: 3)
    /// Saturday 8 August 2026.
    static let saturday = CalendarDate(year: 2026, month: 8, day: 8)
    /// The day the clocks go forward in central Europe in 2026.
    static let springForward = CalendarDate(year: 2026, month: 3, day: 29)
    /// The day the clocks go back in central Europe in 2026.
    static let fallBack = CalendarDate(year: 2026, month: 10, day: 25)

    static func record(
        on date: CalendarDate,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breaks: [BreakSpan] = [],
        type: DayTypeID? = nil
    ) -> DayRecord {
        DayRecord(date: date, dayTypeID: type, start: start, end: end, breaks: breaks)
    }
}
