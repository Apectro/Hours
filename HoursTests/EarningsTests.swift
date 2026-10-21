import XCTest
@testable import Hours

/// What a day, and a span of days, earns.
///
/// Every figure here is whole cents worked out from whole minutes, rounded to
/// the cent once per day, so a month is exactly the sum of its days.
final class EarningsTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// 15.00 an hour, every surcharge off unless a test turns it on.
    private let fifteen = PayRules(hourlyRateCents: 15_00)

    /// Sunday 9 August 2026.
    private let sunday = Fixture.date(2026, 8, 9)

    private func settings(
        _ rules: PayRules,
        breaksArePaid: Bool = false,
        configure: (inout AppSettings) -> Void = { _ in }
    ) -> AppSettings {
        var settings = Fixture.settings()
        settings.primaryBreaksArePaid = breaksArePaid
        settings.changePay(forJob: Job.primaryID, to: rules, from: nil)
        configure(&settings)
        return settings
    }

    private func shift(_ start: TimeOfDay, _ end: TimeOfDay, breakMinutes: Int = 0, job: UUID? = nil) -> Shift {
        Shift(start: start, end: end, breaks: breakMinutes > 0 ? [.duration(breakMinutes)] : [], jobID: job)
    }

    private func records(_ records: [DayRecord]) -> [Int: DayRecord] {
        Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// The summary over `range`, with every record handed over: the engine
    /// is given whole weeks, as the app gives it.
    private func summary(
        _ settings: AppSettings,
        in range: CalendarDateRange,
        records: [DayRecord],
        holidays: [HolidayRule] = [],
        countingThrough: CalendarDate? = nil,
        firstRecorded: CalendarDate? = Fixture.longAgo
    ) -> EarningsSummary? {
        Fixture.engine(settings: settings, calendar: calendar, firstRecorded: firstRecorded)
            .earnings(in: range, records: self.records(records), holidays: holidays, countingThrough: countingThrough)
    }

    private func day(
        _ settings: AppSettings,
        _ record: DayRecord,
        others: [DayRecord] = [],
        holidays: [HolidayRule] = []
    ) -> DayEarnings? {
        summary(settings, in: CalendarDateRange(single: record.date), records: [record] + others, holidays: holidays)?
            .days.first
    }

    private func worked(_ date: CalendarDate, _ start: Int, _ end: Int, breakMinutes: Int = 0) -> DayRecord {
        DayRecord(date: date, shifts: [shift(Fixture.time(start), Fixture.time(end), breakMinutes: breakMinutes)])
    }

    // MARK: - The rate

    func testWorkedHoursEarnTheRate() {
        let result = day(settings(fifteen), worked(Fixture.workingTuesday, 8, 16, breakMinutes: 30))

        XCTAssertEqual(result?.breakdown.baseCents, 112_50, "7:30 at 15.00")
        XCTAssertEqual(result?.totalCents, 112_50)
    }

    func testAPaidBreakIsPaid() {
        let result = day(
            settings(fifteen, breaksArePaid: true),
            worked(Fixture.workingTuesday, 8, 16, breakMinutes: 30)
        )

        XCTAssertEqual(result?.breakdown.baseCents, 120_00)
    }

    func testRoundedWorkedTimeIsWhatIsPaid() {
        var rules = fifteen
        rules.hourlyRateCents = 12_00
        let settings = settings(rules) { $0.rounding = .nearestQuarterHour }

        // 08:00–16:10 rounds to 8:15.
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [shift(Fixture.time(8), Fixture.time(16, 10))])

        XCTAssertEqual(day(settings, record)?.breakdown.baseCents, 99_00)
    }

    func testADayIsRoundedToTheCentOnce() {
        var rules = fifteen
        rules.hourlyRateCents = 10_01
        // 7 minutes at 10.01 an hour is 1.16783…, which is 1.17.
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [shift(Fixture.time(8), Fixture.time(8, 7))])

        XCTAssertEqual(day(settings(rules), record)?.totalCents, 1_17)
    }

    func testTheComponentsAddUpToTheTotalExactly() {
        var rules = fifteen
        rules.hourlyRateCents = 13_33
        rules.nightPercent = 17
        rules.saturdayPercent = 13
        // Saturday 21:07–23:58: every component has a fraction of a cent.
        let record = DayRecord(date: Fixture.saturday, shifts: [shift(Fixture.time(21, 7), Fixture.time(23, 58))])

        let result = day(settings(rules), record)!
        let parts = result.breakdown
        XCTAssertEqual(
            parts.baseCents + parts.overtimeCents + parts.saturdayCents + parts.sundayAndHolidayCents
                + parts.nightCents + parts.paidAbsenceCents,
            result.totalCents
        )
        // 171 minutes at 13.33 is 37.99; 13 % of it 4.94; 118 night minutes at 17 % 4.46.
        XCTAssertEqual(result.totalCents, 47_39)
    }

    func testEachShiftEarnsAtItsOwnJobsRate() {
        let side = Job(name: "Bar", breaksArePaid: true)
        let settings = settings(fifteen) { settings in
            settings.addJob(side)
            settings.changePay(forJob: side.id, to: PayRules(hourlyRateCents: 20_00), from: nil)
        }
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [
            shift(Fixture.time(8), Fixture.time(12), breakMinutes: 30, job: Job.primaryID),
            shift(Fixture.time(18), Fixture.time(21), breakMinutes: 30, job: side.id),
        ])

        // 3:30 at 15.00, and three hours at 20.00 with the break paid.
        XCTAssertEqual(day(settings, record)?.breakdown.baseCents, 52_50 + 60_00)
    }

    func testAJobWithNoRateEarnsNothing() {
        let side = Job(name: "Favour")
        let settings = settings(fifteen) { $0.addJob(side) }
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [
            shift(Fixture.time(8), Fixture.time(12), job: Job.primaryID),
            shift(Fixture.time(13), Fixture.time(17), job: side.id),
        ])

        XCTAssertEqual(day(settings, record)?.totalCents, 60_00)
    }

    // MARK: - Surcharges

    func testSaturdayHoursEarnTheSaturdaySurcharge() {
        var rules = fifteen
        rules.saturdayPercent = 25

        let result = day(settings(rules), worked(Fixture.saturday, 8, 12))

        XCTAssertEqual(result?.breakdown.baseCents, 60_00)
        XCTAssertEqual(result?.breakdown.saturdayCents, 15_00)
        XCTAssertEqual(result?.saturdayMinutes, 240)
        XCTAssertEqual(result?.totalCents, 75_00)
    }

    func testSundayHoursEarnTheSundaySurcharge() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 50

        let result = day(settings(rules), worked(sunday, 8, 12))

        XCTAssertEqual(result?.breakdown.sundayAndHolidayCents, 30_00)
        XCTAssertEqual(result?.totalCents, 90_00)
    }

    func testAPublicHolidayEarnsTheSundaySurcharge() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 100
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))

        // Worked on the holiday, recorded as an ordinary working day.
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .work,
            shifts: [shift(Fixture.time(8), Fixture.time(12))]
        )

        XCTAssertEqual(day(settings(rules), record, holidays: [holiday])?.breakdown.sundayAndHolidayCents, 60_00)
    }

    func testAHolidayThatCountsAsAWorkingDayEarnsNoSurcharge() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 100
        let holiday = HolidayRule(name: "Local", recurrence: .annual(month: 8, day: 4), countsAsWorkingDay: true)

        let result = day(settings(rules), worked(Fixture.workingTuesday, 8, 12), holidays: [holiday])

        XCTAssertEqual(result?.breakdown.sundayAndHolidayCents, 0)
    }

    func testAHolidayOnASaturdayPaysTheHolidayRateAlone() {
        var rules = fifteen
        rules.saturdayPercent = 25
        rules.sundayAndHolidayPercent = 100
        let holiday = HolidayRule(name: "Feast", recurrence: .annual(month: 8, day: 8))

        let result = day(settings(rules), worked(Fixture.saturday, 8, 12), holidays: [holiday])

        XCTAssertEqual(result?.breakdown.saturdayCents, 0)
        XCTAssertEqual(result?.breakdown.sundayAndHolidayCents, 60_00)
    }

    func testNightHoursEarnTheNightSurcharge() {
        var rules = fifteen
        rules.nightPercent = 25

        // 20:00–04:00 against 22:00–06:00: six hours of night, across midnight.
        let result = day(settings(rules), worked(Fixture.workingTuesday, 20, 4))

        XCTAssertEqual(result?.nightMinutes, 360)
        XCTAssertEqual(result?.breakdown.nightCents, 22_50)
        XCTAssertEqual(result?.breakdown.baseCents, 120_00)
    }

    func testANightWindowWithinOneDay() {
        var rules = fifteen
        rules.nightPercent = 10
        rules.nightStart = Fixture.time(0)
        rules.nightEnd = Fixture.time(4)

        let result = day(settings(rules), worked(Fixture.workingTuesday, 22, 6))

        XCTAssertEqual(result?.nightMinutes, 240)
    }

    func testASaturdayNightShiftSplitsAtMidnight() {
        var rules = fifteen
        rules.saturdayPercent = 25
        rules.sundayAndHolidayPercent = 50

        let result = day(settings(rules), worked(Fixture.saturday, 20, 4))

        XCTAssertEqual(result?.saturdayMinutes, 240)
        XCTAssertEqual(result?.sundayAndHolidayMinutes, 240)
        XCTAssertEqual(result?.breakdown.saturdayCents, 15_00)
        XCTAssertEqual(result?.breakdown.sundayAndHolidayCents, 30_00)
    }

    func testANightShiftIntoAHolidayEarnsTheHolidayFromMidnight() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 100
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 5))

        let result = day(settings(rules), worked(Fixture.workingTuesday, 22, 2), holidays: [holiday])

        XCTAssertEqual(result?.sundayAndHolidayMinutes, 120)
    }

    func testSurchargesOnTheSameMinuteAddUp() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 50
        rules.nightPercent = 25
        rules.overtimeMode = .afterDailyHours
        rules.overtimePercent = 30

        // Sunday 22:00–24:00: nothing is expected on a Sunday, so it is all
        // overtime, all Sunday and all night.
        let result = day(settings(rules), worked(sunday, 22, 0))!

        XCTAssertEqual(result.breakdown.baseCents, 30_00)
        XCTAssertEqual(result.breakdown.sundayAndHolidayCents, 15_00)
        XCTAssertEqual(result.breakdown.nightCents, 7_50)
        XCTAssertEqual(result.breakdown.overtimeCents, 9_00)
        XCTAssertEqual(result.totalCents, 61_50)
    }

    // MARK: - Where the breaks were

    func testATimedBreakIsTakenOutWhereItWas() {
        var rules = fifteen
        rules.nightPercent = 10
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [
            Shift(start: Fixture.time(18), end: Fixture.time(2),
                  breaks: [.timed(from: Fixture.time(23), to: Fixture.time(23, 30))]),
        ])

        // Four hours of night, half an hour of it on a break.
        XCTAssertEqual(day(settings(rules), record)?.nightMinutes, 210)
    }

    func testABreakWithNoTimesIsTakenFromTheMiddleOfTheShift() {
        var rules = fifteen
        rules.nightPercent = 10

        // 18:00–02:00 with half an hour off: the middle is 22:00, so the
        // break is 21:45–22:15 and a quarter of an hour of it was night.
        let result = day(settings(rules), worked(Fixture.workingTuesday, 18, 2, breakMinutes: 30))

        XCTAssertEqual(result?.nightMinutes, 225)
    }

    func testAPaidBreakStaysInTheNight() {
        var rules = fifteen
        rules.nightPercent = 10
        let record = worked(Fixture.workingTuesday, 22, 6, breakMinutes: 30)

        XCTAssertEqual(day(settings(rules, breaksArePaid: true), record)?.nightMinutes, 480)
    }

    // MARK: - Overtime

    func testDailyOvertimeIsTheLastMinutesOfTheDay() {
        var rules = fifteen
        rules.overtimeMode = .afterDailyHours
        rules.overtimePercent = 25
        rules.nightPercent = 10
        rules.nightStart = Fixture.time(18)

        // 08:00–18:30 less 30 minutes is ten hours on an eight-hour day. The
        // last two are overtime, and the half hour after 18:00 is night too.
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [shift(Fixture.time(8), Fixture.time(18, 30), breakMinutes: 30)]
        )
        let result = day(settings(rules), record)!

        XCTAssertEqual(result.overtimeMinutes, 120)
        XCTAssertEqual(result.nightMinutes, 30)
        XCTAssertEqual(result.breakdown.overtimeCents, 7_50)
        XCTAssertEqual(result.breakdown.nightCents, 75)
    }

    func testANormalDayCanBeSetByHand() {
        var rules = fifteen
        rules.overtimeMode = .afterDailyHours
        rules.overtimePercent = 50
        rules.dailyThresholdMinutes = 6 * 60

        let result = day(settings(rules), worked(Fixture.workingTuesday, 8, 16))

        XCTAssertEqual(result?.overtimeMinutes, 120)
        XCTAssertEqual(result?.breakdown.overtimeCents, 15_00)
    }

    func testSameRateHasNoOvertime() {
        let result = day(settings(fifteen), worked(Fixture.workingTuesday, 6, 20))

        XCTAssertEqual(result?.overtimeMinutes, 0)
        XCTAssertEqual(result?.breakdown.overtimeCents, 0)
    }

    func testWeeklyOvertimeComesAtTheEndOfTheWeek() {
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 50
        let week = (3...7).map { worked(Fixture.date(2026, 8, $0), 7, 16) }

        let result = summary(
            settings(rules),
            in: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9)),
            records: week
        )!

        // Nine hours a day against forty a week: Friday's last five.
        XCTAssertEqual(result.days.map(\.overtimeMinutes), [0, 0, 0, 0, 300, 0, 0])
        XCTAssertEqual(result.breakdown.overtimeCents, 37_50)
    }

    func testAWeekCutByTheStartOfAMonthIsStillAWholeWeek() {
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 50
        // Monday 28 September to Friday 2 October 2026, ten hours a day.
        let week = [28, 29, 30].map { worked(Fixture.date(2026, 9, $0), 7, 17) }
            + [1, 2].map { worked(Fixture.date(2026, 10, $0), 7, 17) }
        let october = CalendarDateRange.month(YearMonth(year: 2026, month: 10), in: calendar)

        let result = summary(settings(rules), in: october, records: week)!

        // Forty hours were reached on Thursday 1 October; Friday is all overtime.
        XCTAssertEqual(result.days.first { $0.date == Fixture.date(2026, 10, 1) }?.overtimeMinutes, 0)
        XCTAssertEqual(result.days.first { $0.date == Fixture.date(2026, 10, 2) }?.overtimeMinutes, 600)
        XCTAssertEqual(result.breakdown.baseCents, 300_00, "October's own twenty hours")
        XCTAssertEqual(result.breakdown.overtimeCents, 75_00)
    }

    func testAWeeklyThresholdCanBeSetByHand() {
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 100
        rules.weeklyThresholdMinutes = 30 * 60
        let week = (3...6).map { worked(Fixture.date(2026, 8, $0), 8, 16) }

        let result = summary(
            settings(rules),
            in: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9)),
            records: week
        )!

        XCTAssertEqual(result.days.map(\.overtimeMinutes), [0, 0, 0, 120, 0, 0, 0])
    }

    func testPaidAbsenceCountsTowardsTheWeekButIsNotOvertime() {
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 50
        // Leave on Monday, then eight hours Tuesday to Saturday.
        let week = [DayRecord(date: Fixture.date(2026, 8, 3), dayTypeID: .vacation)]
            + (4...8).map { worked(Fixture.date(2026, 8, $0), 8, 16) }

        let result = summary(
            settings(rules),
            in: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9)),
            records: week
        )!

        XCTAssertEqual(result.days.map(\.overtimeMinutes), [0, 0, 0, 0, 0, 480, 0])
    }

    func testCreditedHoursAreNeverThemselvesOvertime() {
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 50
        rules.weeklyThresholdMinutes = 4 * 60
        // A day's leave alone is past a four-hour week; the two hours worked
        // after it are overtime, the leave is not.
        let week = [
            DayRecord(date: Fixture.date(2026, 8, 3), dayTypeID: .vacation),
            worked(Fixture.date(2026, 8, 4), 8, 10),
        ]

        let result = summary(
            settings(rules),
            in: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9)),
            records: week
        )!

        XCTAssertEqual(result.days.map(\.overtimeMinutes), [0, 120, 0, 0, 0, 0, 0])
    }

    // MARK: - Paid absence

    func testPaidAbsenceEarnsItsCreditedHours() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)

        let result = day(settings(fifteen), record)

        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 120_00)
        XCTAssertEqual(result?.breakdown.baseCents, 0)
    }

    func testPaidAbsenceCanBeSetToEarnNothing() {
        var rules = fifteen
        rules.paidAbsenceEarns = false

        let result = day(settings(rules), DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick))

        XCTAssertEqual(result?.totalCents, 0)
    }

    func testPaidAbsenceTakesNoSurcharge() {
        var rules = fifteen
        rules.sundayAndHolidayPercent = 100
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))

        let result = day(settings(rules), DayRecord(date: Fixture.workingTuesday), holidays: [holiday])

        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 120_00)
        XCTAssertEqual(result?.breakdown.sundayAndHolidayCents, 0)
    }

    // MARK: - Spans

    func testARateChangeMidMonthPaysEachDayItsOwnRate() {
        let settings = settings(fifteen) { settings in
            settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 18_00), from: Fixture.date(2026, 8, 5))
        }
        let days = [worked(Fixture.date(2026, 8, 4), 8, 16), worked(Fixture.date(2026, 8, 5), 8, 16)]

        let result = summary(settings, in: CalendarDateRange.month(YearMonth(year: 2026, month: 8), in: calendar), records: days)

        XCTAssertEqual(result?.days.first { $0.date == Fixture.date(2026, 8, 4) }?.totalCents, 120_00)
        XCTAssertEqual(result?.days.first { $0.date == Fixture.date(2026, 8, 5) }?.totalCents, 144_00)
        XCTAssertEqual(result?.totalCents, 264_00)
    }

    func testAMonthIsTheSumOfItsDays() {
        var rules = fifteen
        rules.hourlyRateCents = 13_37
        rules.nightPercent = 13
        rules.saturdayPercent = 7
        rules.overtimeMode = .afterDailyHours
        rules.overtimePercent = 33
        let days = (1...31).map { day in
            DayRecord(date: Fixture.date(2026, 8, day), shifts: [shift(Fixture.time(7, day), Fixture.time(18, 59 - day))])
        }

        let result = summary(settings(rules), in: CalendarDateRange.month(YearMonth(year: 2026, month: 8), in: calendar), records: days)!

        XCTAssertEqual(result.totalCents, result.days.reduce(0) { $0 + $1.totalCents })
        XCTAssertEqual(result.breakdown.nightCents, result.days.reduce(0) { $0 + $1.breakdown.nightCents })
        XCTAssertEqual(result.months.map(\.breakdown), [result.breakdown])
    }

    func testMonthsAreListedOneByOne() {
        let days = [worked(Fixture.date(2026, 7, 31), 8, 16), worked(Fixture.date(2026, 8, 3), 8, 12)]
        let range = CalendarDateRange(start: Fixture.date(2026, 7, 1), end: Fixture.date(2026, 8, 31))

        let result = summary(settings(fifteen), in: range, records: days)!

        XCTAssertEqual(result.months.map(\.month), [YearMonth(year: 2026, month: 7), YearMonth(year: 2026, month: 8)])
        XCTAssertEqual(result.months.map(\.breakdown.totalCents), [120_00, 60_00])
    }

    func testDaysStillToComeEarnNothing() {
        // Leave booked for Thursday, looked at on Tuesday.
        let days = [
            worked(Fixture.date(2026, 8, 4), 8, 16),
            DayRecord(date: Fixture.date(2026, 8, 6), dayTypeID: .vacation),
        ]

        let result = summary(
            settings(fifteen),
            in: CalendarDateRange.month(YearMonth(year: 2026, month: 8), in: calendar),
            records: days,
            countingThrough: Fixture.date(2026, 8, 4)
        )

        XCTAssertEqual(result?.totalCents, 120_00)
    }

    func testDaysBeforeTheBalanceStartsEarnNothing() {
        let settings = settings(fifteen) { $0.balanceStartDate = Fixture.date(2026, 8, 5) }
        let days = [worked(Fixture.date(2026, 8, 4), 8, 16), worked(Fixture.date(2026, 8, 5), 8, 16)]

        let result = summary(settings, in: CalendarDateRange.month(YearMonth(year: 2026, month: 8), in: calendar), records: days)

        XCTAssertEqual(result?.totalCents, 120_00)
    }

    func testAnExcludedDayEarnsNothing() {
        var record = worked(Fixture.workingTuesday, 8, 16)
        record.isIncluded = false

        let result = summary(settings(fifteen), in: CalendarDateRange(single: record.date), records: [record])

        XCTAssertEqual(result?.totalCents, 0)
        XCTAssertEqual(result?.days, [], "an excluded day is not one of the days that earned")
    }

    func testNothingIsWorkedOutWithoutARate() {
        let result = summary(
            Fixture.settings(),
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [worked(Fixture.workingTuesday, 8, 16)]
        )

        XCTAssertNil(result)
    }

    func testTheWeeksAroundARangeAreWhatToFetch() {
        let engine = Fixture.engine(settings: settings(fifteen), calendar: calendar)

        let fetched = engine.earningsRange(covering: CalendarDateRange.month(YearMonth(year: 2026, month: 10), in: calendar))

        XCTAssertEqual(fetched.start, Fixture.date(2026, 9, 28), "the Monday of the week 1 October is in")
        XCTAssertEqual(fetched.end, Fixture.date(2026, 11, 1))
    }
}
