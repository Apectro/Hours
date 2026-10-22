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
    /// The earliest day anything was recorded on — a day, a site day — or
    /// nil when nothing has been. The app reads it from the store; it is an
    /// input rather than something worked out here because finding it means
    /// looking at every day ever recorded, and the store can answer that with
    /// one sorted fetch.
    let firstRecorded: CalendarDate?

    private let calculator: WorkdayCalculator

    init(settings: AppSettings, calendar: Calendar, firstRecorded: CalendarDate?) {
        self.settings = settings
        self.calendar = calendar
        self.firstRecorded = firstRecorded
        self.calculator = WorkdayCalculator(settings: settings, calendar: calendar)
    }

    /// The first day the balance counts: the start date when one is set,
    /// otherwise the first day anything was recorded. Nil when there is
    /// neither, and then no day counts at all.
    ///
    /// A start date wins in both directions. Earlier than the first entry, it
    /// says the days in between were owed — the job began before the app
    /// did. Later, it says the days before it are settled.
    var balanceStart: CalendarDate? {
        settings.balanceStartDate ?? firstRecorded
    }

    /// `balanceStart`, moved back to any day in `records` that has something
    /// on it. The first recorded day is read before a save can add an earlier
    /// one, and a day the person has just written must never be the day that
    /// is left out.
    private func balanceStart(covering records: [Int: DayRecord]) -> CalendarDate? {
        if let explicit = settings.balanceStartDate { return explicit }
        let earliestHere = records.values.filter { !$0.isBlank }.map(\.date).min()
        switch (firstRecorded, earliestHere) {
        case let (first?, here?): return Swift.min(first, here)
        case let (first, here): return first ?? here
        }
    }

    /// Every day in the range, in ascending order, whether or not it has an
    /// entry — a day with no data still has expected hours and still counts,
    /// from the day the balance starts.
    func days(
        in range: CalendarDateRange,
        records: [Int: DayRecord],
        holidays: [HolidayRule]
    ) -> [DayComputation] {
        let resolver = HolidayResolver(rules: holidays, calendar: calendar, covering: range)
        let start = balanceStart(covering: records)
        return range.days(in: calendar).map { date in
            var day = calculator.compute(
                record: records[date.key],
                on: date,
                holiday: resolver.primaryHoliday(on: date)
            )
            day.precedesBalanceStart = start.map { date < $0 } ?? true
            return day
        }
    }

    /// One day on its own, for the day editor and the site screen. Where it
    /// falls against the balance start is a question about a span, so it is
    /// not asked here.
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

    /// The whole weeks around `range`, which is what earnings need records
    /// for: overtime after the contracted week is counted from the week's
    /// first day, so a month starting on a Thursday needs that Monday.
    func earningsRange(covering range: CalendarDateRange) -> CalendarDateRange {
        CalendarDateRange(
            start: CalendarDateRange.week(containing: range.start, in: calendar).start,
            end: CalendarDateRange.week(containing: range.end, in: calendar).end
        )
    }

    /// What the days in `range` earned, or nil when no job has a rate.
    ///
    /// `records` should cover `earningsRange(covering:)`. The weeks are
    /// worked out whole and only then cut to `range`, so a week split by the
    /// start of a month puts its overtime on the same days whichever month
    /// is being looked at. Days after `countingThrough` earn nothing yet.
    func earnings(
        in range: CalendarDateRange,
        records: [Int: DayRecord],
        holidays: [HolidayRule],
        countingThrough: CalendarDate? = nil
    ) -> EarningsSummary? {
        guard settings.earningsAreSetUp else { return nil }
        let weeks = earningsRange(covering: range)
        let days = days(in: weeks, records: records, holidays: holidays)
        // A day longer, for a shift that runs past midnight into a holiday.
        let resolver = HolidayResolver(
            rules: holidays,
            calendar: calendar,
            covering: CalendarDateRange(start: weeks.start, end: weeks.end.adding(days: 1, in: calendar))
        )
        let earned = EarningsCalculator(settings: settings, calendar: calendar, holidays: resolver)
            .earnings(for: days)
        let counted = zip(days, earned)
            .filter { day, _ in range.contains(day.date) && EarningsSummary.counts(day, through: countingThrough) }
            .map(\.1)
        return EarningsSummary(range: range, days: counted)
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

        for day in days where day.counts(through: countingThrough) {

            for shift in day.shifts where shift.workedMinutes > 0 {
                let id = shift.jobID ?? Job.primaryID
                worked[id, default: 0] += shift.workedMinutes
                daysWorked[id, default: []].insert(day.date.key)
            }

            guard settings.features.trackExpectedHours else { continue }
            let weekday = day.date.weekday(in: calendar)
            for job in jobs {
                // `expectedMinutes`, not the raw per-day figure: a weekly
                // override is the contract, and the day's own expectation —
                // the month total beside this card — is built from it.
                let contracted = job.schedule(on: day.date).expectedMinutes(forWeekday: weekday)
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
    /// `working` is the "I worked" answer on a public holiday (or any day
    /// whose type hides the times): the type stays as it resolves — so a
    /// public holiday is still paid — and the times come from the week.
    func draftRecord(for date: CalendarDate, holidays: [HolidayRule], working: Bool = false) -> DayRecord {
        // The week in force on that day, not today's: a day in October is
        // pre-filled with October's hours after a change in November.
        let schedule = settings.primarySchedule(on: date)
        let resolver = HolidayResolver(
            rules: holidays,
            calendar: calendar,
            covering: CalendarDateRange(single: date)
        )
        let holiday = settings.features.trackHolidays ? resolver.primaryHoliday(on: date) : nil
        let typeID = calculator.resolveDayTypeID(record: nil, date: date, holiday: holiday)
        let definition = settings.dayTypeCatalog.definition(for: typeID)

        guard working || (definition.showsTimesByDefault && definition.expectation == .scheduled) else {
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
