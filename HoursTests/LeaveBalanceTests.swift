import XCTest
@testable import Hours

/// The vacation allowance: how much a leave year gives, how much has been
/// taken, how much is booked, and what is left.
final class LeaveBalanceTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func settings(_ policy: LeavePolicy = LeavePolicy(), schedule: WorkSchedule = WorkSchedule()) -> AppSettings {
        var settings = Fixture.settings(schedule: schedule)
        settings.leave = policy
        return settings
    }

    private func vacation(_ date: CalendarDate, expected: Int? = nil) -> DayRecord {
        DayRecord(date: date, dayTypeID: .vacation, expectedOverrideMinutes: expected)
    }

    private func balance(
        _ records: [DayRecord],
        settings: AppSettings,
        today: CalendarDate,
        leaveYear: Int? = nil
    ) -> LeaveBalance {
        let policy = settings.leave
        let year = leaveYear ?? policy.leaveYear(containing: today, calendar: calendar)
        let range = policy.range(ofLeaveYear: year, calendar: calendar)
        let byKey = Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { _, last in last })
        let days = Fixture.engine(settings: settings).days(in: range, records: byKey, holidays: [])
        return LeaveCalculator.balance(
            leaveYear: year, days: days, settings: settings, calendar: calendar, today: today
        )
    }

    // MARK: - The policy

    func testTheDefaultsAreTwentyFiveDaysFromTheFirstOfJanuary() {
        let policy = LeavePolicy()
        XCTAssertEqual(policy.allowanceDays, 25)
        XCTAssertEqual(policy.yearStart, MonthDay(month: 1, day: 1))
        XCTAssertEqual(policy.carriedOverDays, 0)
        XCTAssertNil(policy.carryOverExpires)
    }

    func testOldSettingsReadAsTheDefaultPolicyAndANewOneRoundTrips() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.leave, LeavePolicy())

        var settings = AppSettings()
        settings.leave = LeavePolicy(
            allowanceDays: 30, yearStart: MonthDay(month: 4, day: 1), carriedOverDays: 4.5,
            carriedOverYear: 2026, carryOverExpires: MonthDay(month: 6, day: 30)
        )
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.leave, settings.leave)
    }

    func testABackupCarriesThePolicyAndTheNewDayTypeBothWays() throws {
        var settings = AppSettings()
        settings.leave = LeavePolicy(allowanceDays: 27.5, carriedOverDays: 2, carriedOverYear: 2026)
        let day = DayRecord(date: Fixture.workingTuesday, dayTypeID: .timeOffInLieu)
        let archive = BackupArchive(settings: settings, days: [day], holidays: [])
        let restored = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(restored.settings.leave, settings.leave)
        XCTAssertEqual(restored.days.first?.dayTypeID, .timeOffInLieu)

        // A backup from 1.0 has no leave block and restores with the defaults.
        var json = try JSONSerialization.jsonObject(with: archive.encoded()) as! [String: Any]
        var oldSettings = json["settings"] as! [String: Any]
        oldSettings.removeValue(forKey: "leave")
        json["settings"] = oldSettings
        let old = try BackupArchive.decoded(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.settings.leave, LeavePolicy())
    }

    func testAHalfWrittenPolicyKeepsWhatItCanRead() throws {
        let json = #"{"allowanceDays": 28, "yearStart": "garbage"}"#
        let policy = try JSONDecoder().decode(LeavePolicy.self, from: Data(json.utf8))
        XCTAssertEqual(policy.allowanceDays, 28)
        XCTAssertEqual(policy.yearStart, MonthDay(month: 1, day: 1))
    }

    // MARK: - Leave years

    func testACalendarLeaveYearIsTheCalendarYear() {
        let policy = LeavePolicy()
        XCTAssertEqual(policy.leaveYear(containing: Fixture.date(2026, 1, 1), calendar: calendar), 2026)
        XCTAssertEqual(policy.leaveYear(containing: Fixture.date(2026, 12, 31), calendar: calendar), 2026)
        XCTAssertEqual(
            policy.range(ofLeaveYear: 2026, calendar: calendar),
            CalendarDateRange(start: Fixture.date(2026, 1, 1), end: Fixture.date(2026, 12, 31))
        )
    }

    func testALeaveYearFromAprilIsNamedForTheYearItStarts() {
        let policy = LeavePolicy(yearStart: MonthDay(month: 4, day: 1))
        XCTAssertEqual(policy.leaveYear(containing: Fixture.date(2026, 3, 31), calendar: calendar), 2025)
        XCTAssertEqual(policy.leaveYear(containing: Fixture.date(2026, 4, 1), calendar: calendar), 2026)
        XCTAssertEqual(
            policy.range(ofLeaveYear: 2025, calendar: calendar),
            CalendarDateRange(start: Fixture.date(2025, 4, 1), end: Fixture.date(2026, 3, 31))
        )
    }

    func testAStartOnTheTwentyNinthOfFebruaryFallsBackInACommonYear() {
        let policy = LeavePolicy(yearStart: MonthDay(month: 2, day: 29))
        XCTAssertEqual(policy.range(ofLeaveYear: 2027, calendar: calendar).start, Fixture.date(2027, 2, 28))
        XCTAssertEqual(policy.range(ofLeaveYear: 2028, calendar: calendar).start, Fixture.date(2028, 2, 29))
        XCTAssertEqual(policy.range(ofLeaveYear: 2027, calendar: calendar).end, Fixture.date(2028, 2, 28))
    }

    func testDaysEitherSideOfTheBoundaryCountInTheirOwnYear() {
        let policy = LeavePolicy(yearStart: MonthDay(month: 4, day: 1))
        let settings = settings(policy)
        // Tuesday 31 March and Wednesday 1 April 2026.
        let records = [vacation(Fixture.date(2026, 3, 31)), vacation(Fixture.date(2026, 4, 1))]
        let today = Fixture.date(2026, 6, 1)
        XCTAssertEqual(balance(records, settings: settings, today: today, leaveYear: 2025).used, HalfDays(days: 1))
        XCTAssertEqual(balance(records, settings: settings, today: today, leaveYear: 2026).used, HalfDays(days: 1))
    }

    // MARK: - Used, planned, remaining

    func testUsedIsTakenThroughTodayAndPlannedIsBookedAfter() {
        let records = [
            vacation(Fixture.date(2026, 8, 3)), vacation(Fixture.date(2026, 8, 4)),  // Mon, Tue: taken
            vacation(Fixture.date(2026, 8, 5)),                                      // today
            vacation(Fixture.date(2026, 12, 28)), vacation(Fixture.date(2026, 12, 29)) // booked
        ]
        let result = balance(records, settings: settings(), today: Fixture.date(2026, 8, 5))
        XCTAssertEqual(result.allowance, HalfDays(days: 25))
        XCTAssertEqual(result.used, HalfDays(days: 3), "today counts as taken")
        XCTAssertEqual(result.planned, HalfDays(days: 2))
        XCTAssertEqual(result.remaining, HalfDays(days: 20))
    }

    func testAVacationDayOnAWeekendOrAnExcludedDayCostsNothing() {
        var excluded = vacation(Fixture.date(2026, 8, 4))
        excluded.isIncluded = false
        let records = [vacation(Fixture.saturday), excluded]
        let result = balance(records, settings: settings(), today: Fixture.date(2026, 9, 1))
        XCTAssertEqual(result.used, HalfDays(halves: 0))
    }

    func testOnlyVacationCounts() {
        let records = [
            DayRecord(date: Fixture.date(2026, 8, 3), dayTypeID: .sick),
            DayRecord(date: Fixture.date(2026, 8, 4), dayTypeID: .timeOffInLieu),
            DayRecord(date: Fixture.date(2026, 8, 5), dayTypeID: .holiday)
        ]
        let result = balance(records, settings: settings(), today: Fixture.date(2026, 9, 1))
        XCTAssertEqual(result.used, HalfDays(halves: 0))
        XCTAssertEqual(result.remaining, HalfDays(days: 25))
    }

    /// The app has no half-day type: a part day of leave is a vacation day
    /// whose expected hours were set lower by hand. Up to half the day's
    /// contracted hours is half a day of leave; more than that is a day.
    func testAVacationDayWithFewerHoursCountsAsHalfADay() {
        let records = [
            vacation(Fixture.date(2026, 8, 3), expected: 240),  // exactly half
            vacation(Fixture.date(2026, 8, 4), expected: 120),  // a quarter: still half a day
            vacation(Fixture.date(2026, 8, 5), expected: 300),  // more than half: a day
            vacation(Fixture.date(2026, 8, 6), expected: 0)     // nothing credited: nothing taken
        ]
        let result = balance(records, settings: settings(), today: Fixture.date(2026, 9, 1))
        XCTAssertEqual(result.used, HalfDays(halves: 4))
    }

    func testAShortFridayIsStillAWholeDay() {
        var schedule = WorkSchedule()
        schedule.setContractedMinutes(360, forWeekday: 6)
        let result = balance([vacation(Fixture.date(2026, 8, 7))], settings: settings(schedule: schedule), today: Fixture.date(2026, 9, 1))
        XCTAssertEqual(result.used, HalfDays(days: 1))
    }

    func testRemainingCanGoBelowZero() {
        let result = balance(
            [vacation(Fixture.date(2026, 8, 3)), vacation(Fixture.date(2026, 8, 4))],
            settings: settings(LeavePolicy(allowanceDays: 1)),
            today: Fixture.date(2026, 9, 1)
        )
        XCTAssertEqual(result.remaining, HalfDays(days: -1))
    }

    func testAHalfDayAllowanceIsKept() {
        let result = balance([], settings: settings(LeavePolicy(allowanceDays: 22.5)), today: Fixture.date(2026, 9, 1))
        XCTAssertEqual(result.allowance, HalfDays(halves: 45))
        XCTAssertEqual(result.remaining.formatted(decimalSeparator: ","), "22,5")
    }

    // MARK: - Carry-over

    func testCarryOverBelongsToTheLeaveYearItWasEnteredFor() {
        let policy = LeavePolicy(carriedOverDays: 5, carriedOverYear: 2026)
        let thisYear = balance([], settings: settings(policy), today: Fixture.date(2026, 8, 5))
        XCTAssertEqual(thisYear.carried, HalfDays(days: 5))
        XCTAssertEqual(thisYear.remaining, HalfDays(days: 30))
        let nextYear = balance([], settings: settings(policy), today: Fixture.date(2027, 2, 1))
        XCTAssertEqual(nextYear.carried, HalfDays(halves: 0), "last year's carry-over is not carried again")
    }

    func testCarryOverWithNoExpiryIsKeptAllYear() {
        let policy = LeavePolicy(carriedOverDays: 5, carriedOverYear: 2026)
        let result = balance([], settings: settings(policy), today: Fixture.date(2026, 12, 31))
        XCTAssertEqual(result.expired, HalfDays(halves: 0))
        XCTAssertEqual(result.remaining, HalfDays(days: 30))
    }

    func testCarryOverNotUsedByItsExpiryIsLost() {
        let policy = LeavePolicy(carriedOverDays: 5, carriedOverYear: 2026, carryOverExpires: MonthDay(month: 3, day: 31))
        // Two days in February use carry-over first.
        let records = [vacation(Fixture.date(2026, 2, 2)), vacation(Fixture.date(2026, 2, 3))]

        let before = balance(records, settings: settings(policy), today: Fixture.date(2026, 3, 31))
        XCTAssertEqual(before.expired, HalfDays(halves: 0), "the expiry day itself still has it")
        XCTAssertEqual(before.carryOverAtRisk, HalfDays(days: 3))
        XCTAssertEqual(before.carryOverExpiry, Fixture.date(2026, 3, 31))
        XCTAssertEqual(before.remaining, HalfDays(days: 28))

        let after = balance(records, settings: settings(policy), today: Fixture.date(2026, 4, 1))
        XCTAssertEqual(after.expired, HalfDays(days: 3))
        XCTAssertEqual(after.carryOverAtRisk, HalfDays(halves: 0))
        XCTAssertEqual(after.remaining, HalfDays(days: 25), "the allowance is untouched; three carried days went")
    }

    func testLeaveBookedBeforeTheExpiryKeepsTheCarryOverItUses() {
        let policy = LeavePolicy(carriedOverDays: 3, carriedOverYear: 2026, carryOverExpires: MonthDay(month: 3, day: 31))
        // Booked in January for the last week of March.
        let records = [vacation(Fixture.date(2026, 3, 30)), vacation(Fixture.date(2026, 3, 31))]
        let result = balance(records, settings: settings(policy), today: Fixture.date(2026, 1, 15))
        XCTAssertEqual(result.planned, HalfDays(days: 2))
        XCTAssertEqual(result.carryOverAtRisk, HalfDays(days: 1))
        XCTAssertEqual(result.remaining, HalfDays(days: 26))
    }

    func testLeaveAfterTheExpiryDoesNotSaveTheCarryOver() {
        let policy = LeavePolicy(carriedOverDays: 2, carriedOverYear: 2026, carryOverExpires: MonthDay(month: 3, day: 31))
        let records = [vacation(Fixture.date(2026, 4, 1))]
        let result = balance(records, settings: settings(policy), today: Fixture.date(2026, 5, 1))
        XCTAssertEqual(result.expired, HalfDays(days: 2))
        XCTAssertEqual(result.used, HalfDays(days: 1))
        XCTAssertEqual(result.remaining, HalfDays(days: 24))
    }

    func testTheExpiryFollowsALeaveYearThatStartsMidYear() {
        let policy = LeavePolicy(
            yearStart: MonthDay(month: 10, day: 1), carriedOverDays: 2, carriedOverYear: 2026,
            carryOverExpires: MonthDay(month: 1, day: 31)
        )
        let result = balance([], settings: settings(policy), today: Fixture.date(2026, 11, 1))
        XCTAssertEqual(result.carryOverExpiry, Fixture.date(2027, 1, 31))
        XCTAssertEqual(result.carryOverAtRisk, HalfDays(days: 2))
    }

    // MARK: - Half days

    func testHalfDaysFormatWithoutATrailingZero() {
        XCTAssertEqual(HalfDays(halves: 34).formatted(), "17")
        XCTAssertEqual(HalfDays(halves: 35).formatted(), "17.5")
        XCTAssertEqual(HalfDays(halves: 1).formatted(decimalSeparator: ","), "0,5")
        XCTAssertEqual(HalfDays(halves: -3).formatted(), "-1.5")
        XCTAssertEqual(HalfDays(days: 2.4), HalfDays(halves: 5), "rounded to the nearest half")
        XCTAssertEqual(HalfDays(days: 2.2), HalfDays(halves: 4))
    }

    // MARK: - The day editor's line

    func testChoosingVacationForADayShowsWhatWouldBeLeft() {
        let settings = settings()
        let stored = [vacation(Fixture.date(2026, 8, 3))]
        let draft = vacation(Fixture.date(2026, 8, 4))
        let after = balance(stored + [draft], settings: settings, today: Fixture.date(2026, 8, 1))
        XCTAssertEqual(after.remaining, HalfDays(days: 23))
        XCTAssertEqual(LeaveCalculator.halfDays(for: Fixture.engine(settings: settings).day(draft.date, record: draft, holidays: []),
                                                settings: settings, calendar: calendar), 2)
    }
}
