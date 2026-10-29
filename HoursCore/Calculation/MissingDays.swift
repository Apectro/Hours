import Foundation

/// Which of your own days are "not written": the one definition the
/// calendar's banner, the export's warning and the gap reminder share.
///
/// A missing day is exactly what the gap reminder nudges about
/// (`DayComputation.isUnrecordedWorkingDay`): a scheduled working day, from
/// the day the balance starts, included, with nothing on it, before today.
/// So days off, excluded days, public holidays, leave, today and every day
/// after it never count. For a site's days see `SiteDayStatus`.
enum MissingDays {
    /// The missing days among days already computed, in their order.
    static func personal(days: [DayComputation], today: CalendarDate) -> [CalendarDate] {
        GapFinder.unrecordedWorkingDays(in: days, asOf: today)
    }

    /// The missing days in `range`, in order, computed from what is stored.
    /// `firstRecorded` is the first day anything was ever recorded (the
    /// store's `firstRecordedDate()`): with no balance start date set, days
    /// before it are not counted, as everywhere else.
    static func personal(
        records: [Int: DayRecord],
        holidays: [HolidayRule],
        settings: AppSettings,
        calendar: Calendar,
        range: CalendarDateRange,
        today: CalendarDate,
        firstRecorded: CalendarDate?
    ) -> [CalendarDate] {
        // Nothing from today on can be missing, so it is not computed.
        let yesterday = today.adding(days: -1, in: calendar)
        guard range.start <= yesterday else { return [] }
        let past = CalendarDateRange(start: range.start, end: min(range.end, yesterday))
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: firstRecorded)
            .days(in: past, records: records, holidays: holidays)
        return personal(days: days, today: today)
    }
}
