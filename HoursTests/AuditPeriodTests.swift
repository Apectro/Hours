import XCTest
@testable import Hours

/// The calculation audit, period level: weeks, months and the split by job
/// against the days they are made of.
final class AuditPeriodTests: XCTestCase {
    private let calendar = Fixture.calendar()

    // MARK: - By job

    /// A contract of 37½ hours set as the weekly override, over days that
    /// sum to forty. The month's expected hours follow the override; the
    /// "By job" card on the statistics screen must say the same, or the one
    /// job shows a 2½ hour shortfall every week that the month does not.
    func testAJobsExpectedHoursFollowItsWeeklyOverride() {
        var settings = Fixture.settings()
        var contract = WorkSchedule()
        contract.weeklyTargetOverrideMinutes = 37 * 60 + 30
        settings.setPrimarySchedule(contract)
        settings.addJob(Job(name: "Evenings", schedule: WorkSchedule(minutesByWeekday: [0, 120, 120, 0, 0, 0, 0])))

        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let week = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))
        let days = engine.days(in: week, records: [:], holidays: [])
        let summary = PeriodAggregator.summarize(days, range: week)
        let byJob = engine.jobTotals(for: days)

        let primary = byJob.first { $0.job.isPrimary }
        XCTAssertEqual(primary?.expectedMinutes, 37 * 60 + 30)
        XCTAssertEqual(byJob.map(\.expectedMinutes).reduce(0, +), summary.expectedMinutes)
    }

    // MARK: - Totals are the sum of their days

    /// Random months of mixed days: worked, split, overnight, absent,
    /// excluded, adjusted, in the future. Every figure in the summary must
    /// be the plain sum of the days it counts.
    private func randomMonth(
        _ month: YearMonth,
        settings: AppSettings,
        seed: UInt64
    ) -> [Int: DayRecord] {
        var generator = SeededGenerator(seed: seed)
        var records: [Int: DayRecord] = [:]
        let types: [DayTypeID?] = [nil, nil, nil, nil, .vacation, .sick, .holiday, .weekend, .dayOff]
        for date in month.range(in: calendar).days(in: calendar) where Int.random(in: 0..<10, using: &generator) < 8 {
            let start = Int.random(in: 0..<1440, using: &generator)
            let length = Int.random(in: 0..<720, using: &generator)
            var record = DayRecord(
                date: date,
                dayTypeID: types.randomElement(using: &generator)!,
                start: TimeOfDay(minutes: start),
                end: TimeOfDay(minutes: (start + length) % 1440),
                breaks: [.duration(Int.random(in: 0...60, using: &generator))]
            )
            if Int.random(in: 0..<6, using: &generator) == 0 {
                record.shifts.append(Shift(start: Fixture.time(19), end: Fixture.time(21)))
            }
            if Int.random(in: 0..<8, using: &generator) == 0 { record.isIncluded = false }
            if Int.random(in: 0..<8, using: &generator) == 0 {
                record.adjustmentMinutes = Int.random(in: -120...120, using: &generator)
            }
            if Int.random(in: 0..<10, using: &generator) == 0 {
                record.expectedOverrideMinutes = Int.random(in: 0...600, using: &generator)
            }
            records[date.key] = record
        }
        return records
    }

    func testEveryMonthlyFigureIsTheSumOfTheDaysThatCount() {
        for (index, rounding) in RoundingRule.allCases.enumerated() {
            for policy in DurationPolicy.allCases {
                let settings = Fixture.settings(rounding: rounding, durationPolicy: policy)
                let engine = Fixture.engine(settings: settings, calendar: calendar)
                for month in [YearMonth(year: 2026, month: 3), YearMonth(year: 2026, month: 10), YearMonth(year: 2028, month: 2)] {
                    let records = randomMonth(month, settings: settings, seed: UInt64(month.month * 100 + index + 1))
                    let range = month.range(in: calendar)
                    let cutoff = CalendarDate(year: month.year, month: month.month, day: 17)
                    let days = engine.days(in: range, records: records, holidays: [])
                    let summary = PeriodAggregator.summarize(days, range: range, countingThrough: cutoff)
                    let counted = days.filter { $0.counts(through: cutoff) }

                    XCTAssertEqual(summary.workedMinutes, counted.map(\.workedMinutes).reduce(0, +))
                    XCTAssertEqual(summary.creditedMinutes, counted.map(\.creditedMinutes).reduce(0, +))
                    XCTAssertEqual(summary.expectedMinutes, counted.map(\.expectedMinutes).reduce(0, +))
                    XCTAssertEqual(summary.breakMinutes, counted.map(\.breakMinutes).reduce(0, +))
                    XCTAssertEqual(summary.balanceMinutes, counted.map(\.balanceMinutes).reduce(0, +))
                    XCTAssertEqual(summary.overtimeMinutes - summary.deficitMinutes, summary.balanceMinutes)
                    XCTAssertEqual(
                        summary.balanceMinutes,
                        summary.paidMinutes - summary.expectedMinutes + summary.adjustmentMinutes
                    )
                    XCTAssertEqual(summary.daysWorked, counted.filter { $0.workedMinutes > 0 }.count)
                    XCTAssertEqual(summary.countsByType.values.reduce(0, +), counted.count)
                    // No day after the cut-off with nothing on it is counted.
                    XCTAssertFalse(counted.contains { $0.date > cutoff && !$0.hasEntry })
                    // Each day's worked time is the sum of its shifts when no
                    // rounding is in play.
                    if rounding == .exact {
                        for day in days {
                            XCTAssertEqual(day.workedMinutes, day.shifts.map(\.workedMinutes).reduce(0, +))
                        }
                    }
                }
            }
        }
    }

    /// The weeks of a month, clipped to it, add up to the month — whichever
    /// day the week starts on.
    func testTheWeeksOfAMonthAddUpToTheMonth() {
        for firstWeekday in [1, 2, 7] {
            let calendar = Fixture.calendar(firstWeekday: firstWeekday)
            let settings = Fixture.settings()
            let engine = Fixture.engine(settings: settings, calendar: calendar)
            let month = YearMonth(year: 2026, month: 3)
            let range = month.range(in: calendar)
            let records = randomMonth(month, settings: settings, seed: UInt64(firstWeekday))
            let whole = engine.summary(in: range, records: records, holidays: [])

            var worked = 0, expected = 0, balance = 0, cursor = range.start
            while cursor <= range.end {
                let week = CalendarDateRange.week(containing: cursor, in: calendar)
                XCTAssertEqual(week.start.weekday(in: calendar), firstWeekday)
                let clipped = CalendarDateRange(start: max(week.start, range.start), end: min(week.end, range.end))
                let part = engine.summary(in: clipped, records: records, holidays: [])
                worked += part.workedMinutes
                expected += part.expectedMinutes
                balance += part.balanceMinutes
                cursor = week.end.adding(days: 1, in: calendar)
            }
            XCTAssertEqual(worked, whole.workedMinutes, "first weekday \(firstWeekday)")
            XCTAssertEqual(expected, whole.expectedMinutes, "first weekday \(firstWeekday)")
            XCTAssertEqual(balance, whole.balanceMinutes, "first weekday \(firstWeekday)")
        }
    }

    // MARK: - Expected hours

    /// Expected and credited hours for a month, counted independently: every
    /// weekday is contracted at eight hours, and a public holiday on one is
    /// credited those eight hours; one on a Saturday credits nothing.
    func testExpectedHoursAreTheContractedWeekdaysAndHolidaysAreCredited() {
        let holidays = [
            HolidayRule(name: "New Year", recurrence: .annual(month: 1, day: 1)),
            HolidayRule(name: "Leap", recurrence: .annual(month: 2, day: 29)),
            HolidayRule(name: "Saturday holiday", recurrence: .once(on: Fixture.date(2028, 2, 5)))
        ]
        let engine = Fixture.engine(calendar: calendar)
        for (year, month, length) in [(2028, 2, 29), (2027, 2, 28), (2026, 1, 31), (2026, 3, 31), (2026, 10, 31)] {
            let range = YearMonth(year: year, month: month).range(in: calendar)
            XCTAssertEqual(range.days(in: calendar).count, length, "\(year)-\(month)")
            let summary = engine.summary(in: range, records: [:], holidays: holidays)
            var expected = 0
            var credited = 0
            for date in range.days(in: calendar) where (2...6).contains(date.weekday(in: calendar)) {
                expected += 480
                let isHoliday = (date.month == 1 && date.day == 1) || (date.month == 2 && date.day == 29)
                if isHoliday { credited += 480 }
            }
            XCTAssertEqual(summary.expectedMinutes, expected, "\(year)-\(month)")
            XCTAssertEqual(summary.creditedMinutes, credited, "\(year)-\(month)")
            XCTAssertEqual(summary.balanceMinutes, credited - expected, "\(year)-\(month)")
        }
        // Leap day is a day: February 2028 has 29, and its holiday lands.
        let leap = engine.day(Fixture.date(2028, 2, 29), record: nil, holidays: holidays)
        XCTAssertEqual(leap.dayType.id, .holiday)
        XCTAssertEqual(leap.creditedMinutes, 480)
        // 29 February in a common year does not move to the 28th or 1 March.
        XCTAssertEqual(engine.day(Fixture.date(2027, 2, 28), record: nil, holidays: holidays).dayType.id, .weekend)
        XCTAssertEqual(engine.day(Fixture.date(2027, 3, 1), record: nil, holidays: holidays).dayType.id, .work)
    }

    /// An archived job stops expecting hours from the day it is archived
    /// (there is no date on it: it stops everywhere), but its recorded work
    /// still counts towards the month.
    func testAnArchivedJobExpectsNothingButItsHoursStillCount() {
        var settings = Fixture.settings()
        let old = Job(name: "Old", schedule: WorkSchedule(minutesByWeekday: [0, 240, 240, 240, 240, 240, 0]))
        settings.addJob(old)
        settings.updateJob(id: old.id) { $0.isArchived = true }
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(12), jobID: old.id)]
        )
        let day = engine.day(Fixture.workingTuesday, record: record, holidays: [])
        XCTAssertEqual(day.expectedMinutes, 480)
        XCTAssertEqual(day.workedMinutes, 240)
    }

    // MARK: - Daylight saving across a month

    /// A month of 08:00–16:30 days with a 30-minute break balances to zero
    /// on the wall clock in both transition months; measured as elapsed time
    /// it is out by exactly the hour the clocks moved, and only on the night
    /// shift that spans the change.
    func testATransitionMonthBalancesOnTheWallClock() {
        for month in [YearMonth(year: 2026, month: 3), YearMonth(year: 2026, month: 10)] {
            var records: [Int: DayRecord] = [:]
            for date in month.range(in: calendar).days(in: calendar) where (2...6).contains(date.weekday(in: calendar)) {
                records[date.key] = DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])
            }
            let summary = Fixture.engine(calendar: calendar).summary(in: month.range(in: calendar), records: records, holidays: [])
            XCTAssertEqual(summary.balanceMinutes, 0, "\(month)")

            // A Saturday night shift across the change, 22:00–06:00.
            let saturday = month.month == 3 ? Fixture.date(2026, 3, 28) : Fixture.date(2026, 10, 24)
            records[saturday.key] = DayRecord(date: saturday, start: Fixture.time(22), end: Fixture.time(6))
            let wall = Fixture.engine(calendar: calendar).summary(in: month.range(in: calendar), records: records, holidays: [])
            let real = Fixture.engine(settings: Fixture.settings(durationPolicy: .elapsedReal), calendar: calendar)
                .summary(in: month.range(in: calendar), records: records, holidays: [])
            XCTAssertEqual(wall.workedMinutes - summary.workedMinutes, 480)
            XCTAssertEqual(real.workedMinutes - wall.workedMinutes, month.month == 3 ? -60 : 60, "\(month)")
        }
    }
}
