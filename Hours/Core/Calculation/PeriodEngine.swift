import Foundation

/// Computes whole spans of days.
///
/// The single entry point used by the calendar, the statistics screen and every
/// export: give it a range, the stored records and the holiday rules, and it
/// returns fully resolved days plus their totals. Pure, so all three surfaces
/// are guaranteed to agree.
struct PeriodEngine: Sendable {
    let settings: AppSettings
    let calendar: Calendar

    private let calculator: WorkdayCalculator

    init(settings: AppSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
        self.calculator = WorkdayCalculator(settings: settings, calendar: calendar)
    }

    /// Every day in the range, in ascending order, whether or not it has an
    /// entry — a day with no data still has expected hours and still counts.
    func days(
        in range: CalendarDateRange,
        records: [Int: DayRecord],
        holidays: [HolidayRule]
    ) -> [DayComputation] {
        let resolver = HolidayResolver(rules: holidays, calendar: calendar, covering: range)
        return range.days(in: calendar).map { date in
            calculator.compute(
                record: records[date.key],
                on: date,
                holiday: resolver.primaryHoliday(on: date)
            )
        }
    }

    func day(
        _ date: CalendarDate,
        record: DayRecord?,
        holidays: [HolidayRule]
    ) -> DayComputation {
        let resolver = HolidayResolver(
            rules: holidays,
            calendar: calendar,
            covering: CalendarDateRange(single: date)
        )
        return calculator.compute(record: record, on: date, holiday: resolver.primaryHoliday(on: date))
    }

    func summary(
        in range: CalendarDateRange,
        records: [Int: DayRecord],
        holidays: [HolidayRule],
        countingThrough: CalendarDate? = nil
    ) -> PeriodSummary {
        PeriodAggregator.summarize(
            days(in: range, records: records, holidays: holidays),
            range: range,
            countingThrough: countingThrough
        )
    }

    /// Days and totals in one pass, for screens that need both.
    func resolve(
        in range: CalendarDateRange,
        records: [Int: DayRecord],
        holidays: [HolidayRule],
        countingThrough: CalendarDate? = nil
    ) -> (days: [DayComputation], summary: PeriodSummary) {
        let days = days(in: range, records: records, holidays: holidays)
        return (days, PeriodAggregator.summarize(days, range: range, countingThrough: countingThrough))
    }

    /// The record a brand-new day should start from, pre-filled from the
    /// schedule so the common case is "open, glance, save".
    func draftRecord(for date: CalendarDate, holidays: [HolidayRule]) -> DayRecord {
        let schedule = settings.schedule
        let resolver = HolidayResolver(
            rules: holidays,
            calendar: calendar,
            covering: CalendarDateRange(single: date)
        )
        let holiday = settings.features.trackHolidays ? resolver.primaryHoliday(on: date) : nil
        let typeID = calculator.resolveDayTypeID(record: nil, date: date, holiday: holiday)
        let definition = settings.dayTypeCatalog.definition(for: typeID)

        guard definition.showsTimesByDefault, definition.expectation == .scheduled else {
            return DayRecord(date: date, dayTypeID: typeID)
        }

        return DayRecord(
            date: date,
            dayTypeID: typeID,
            start: schedule.defaultStart,
            end: schedule.defaultEnd,
            breaks: settings.features.trackBreaks && schedule.defaultBreakMinutes > 0
                ? [BreakSpan.duration(schedule.defaultBreakMinutes)]
                : []
        )
    }
}
