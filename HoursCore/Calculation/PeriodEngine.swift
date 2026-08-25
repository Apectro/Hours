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

    /// What one job contributed over a period.
    struct JobTotals: Identifiable, Hashable, Sendable {
        var job: Job
        var workedMinutes: Int
        var creditedMinutes: Int
        var expectedMinutes: Int
        var daysWorked: Int

        var id: UUID { job.id }
        var paidMinutes: Int { workedMinutes + creditedMinutes }
        var balanceMinutes: Int { paidMinutes - expectedMinutes }
    }

    /// Splits a period by job.
    ///
    /// Worked time comes from the shifts, which each know their job. Expected
    /// and credited hours come from each job's own contracted week, so two jobs
    /// with different schedules each get their own honest balance rather than
    /// sharing one.
    func jobTotals(
        for days: [DayComputation],
        countingThrough: CalendarDate? = nil
    ) -> [JobTotals] {
        let jobs = settings.activeJobs
        guard !jobs.isEmpty else { return [] }

        var worked: [UUID: Int] = [:]
        var credited: [UUID: Int] = [:]
        var expected: [UUID: Int] = [:]
        var daysWorked: [UUID: Set<Int>] = [:]

        for day in days where day.isIncluded {
            if let countingThrough, day.date > countingThrough, !day.hasEntry { continue }

            for shift in day.shifts where shift.workedMinutes > 0 {
                let id = shift.jobID ?? Job.primaryID
                worked[id, default: 0] += shift.workedMinutes
                daysWorked[id, default: []].insert(day.date.key)
            }

            guard settings.features.trackExpectedHours else { continue }
            let weekday = day.date.weekday(in: calendar)
            for job in jobs {
                let contracted = job.schedule.contractedMinutes(forWeekday: weekday)
                switch day.dayType.expectation {
                case .zero:
                    continue
                case .scheduled:
                    expected[job.id, default: 0] += contracted
                case .creditedAbsence:
                    expected[job.id, default: 0] += contracted
                    credited[job.id, default: 0] += contracted
                }
            }
        }

        return jobs.map { job in
            JobTotals(
                job: job,
                workedMinutes: worked[job.id] ?? 0,
                creditedMinutes: credited[job.id] ?? 0,
                expectedMinutes: expected[job.id] ?? 0,
                daysWorked: daysWorked[job.id]?.count ?? 0
            )
        }
    }

    /// The record a brand-new day should start from, pre-filled from the
    /// schedule so the common case is "open, glance, save".
    func draftRecord(for date: CalendarDate, holidays: [HolidayRule]) -> DayRecord {
        let schedule = settings.primaryJob.schedule
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
            shifts: [
                Shift(
                    start: schedule.defaultStart,
                    end: schedule.defaultEnd,
                    breaks: settings.features.trackBreaks && schedule.defaultBreakMinutes > 0
                        ? [BreakSpan.duration(schedule.defaultBreakMinutes)]
                        : [],
                    jobID: settings.tracksMultipleJobs ? settings.primaryJob.id : nil
                )
            ]
        )
    }
}
