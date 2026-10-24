import XCTest
@testable import Hours

/// Field allowance (Auslöse, terenski dodatak), kilometres in your own car and
/// travel time: the settings, the day, what a span of days adds up to and
/// what it earns.
final class AllowanceTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Allowance on: 30.00 a day, 0.42 a kilometre.
    private func settings(
        travelCountsAsWork: Bool = false,
        enabled: Bool = true,
        configure: (inout AppSettings) -> Void = { _ in }
    ) -> AppSettings {
        var settings = Fixture.settings()
        settings.allowance = AllowancePreferences(
            isEnabled: enabled,
            dailyAllowanceCents: 30_00,
            centsPerKilometre: 42,
            travelCountsAsWork: travelCountsAsWork
        )
        configure(&settings)
        return settings
    }

    private func workday(
        _ date: CalendarDate = Fixture.workingTuesday,
        allowance: Bool = false,
        km: Int = 0,
        travel: Int = 0
    ) -> DayRecord {
        DayRecord(
            date: date,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)],
            hasFieldAllowance: allowance,
            kilometres: km,
            travelMinutes: travel
        )
    }

    // MARK: - Settings

    func testItIsOffByDefaultAndNothingIsSet() {
        let preferences = AppSettings().allowance
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(preferences.dailyAllowanceCents, 0)
        XCTAssertEqual(preferences.centsPerKilometre, 0)
        XCTAssertFalse(preferences.travelCountsAsWork)
    }

    func testSettingsWrittenBeforeItReadAsOff() throws {
        let old = try JSONEncoder().encode(Fixture.settings())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        object.removeValue(forKey: "allowance")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.allowance, AllowancePreferences())
    }

    func testSettingsRoundTripAndDecodeLeniently() throws {
        let settings = settings(travelCountsAsWork: true)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.allowance, settings.allowance)

        let partial = Data(#"{"isEnabled": true, "centsPerKilometre": "junk"}"#.utf8)
        let lenient = try JSONDecoder().decode(AllowancePreferences.self, from: partial)
        XCTAssertTrue(lenient.isEnabled)
        XCTAssertEqual(lenient.centsPerKilometre, 0)
        XCTAssertEqual(lenient.dailyAllowanceCents, 0)
    }

    func testNegativeAmountsAreNotKept() {
        let preferences = AllowancePreferences(isEnabled: true, dailyAllowanceCents: -5, centsPerKilometre: -1)
        XCTAssertEqual(preferences.dailyAllowanceCents, 0)
        XCTAssertEqual(preferences.centsPerKilometre, 0)
    }

    // MARK: - The day

    func testADayRoundTripsItsAllowanceKilometresAndTravel() throws {
        let day = workday(allowance: true, km: 84, travel: 95)
        let decoded = try JSONDecoder().decode(DayRecord.self, from: JSONEncoder().encode(day))
        XCTAssertEqual(decoded, day)
        XCTAssertTrue(decoded.hasFieldAllowance)
        XCTAssertEqual(decoded.kilometres, 84)
        XCTAssertEqual(decoded.travelMinutes, 95)
    }

    func testADayWrittenBeforeItHasNone() throws {
        let json = Data(#"{"date": 20260804, "note": "old"}"#.utf8)
        let day = try JSONDecoder().decode(DayRecord.self, from: json)
        XCTAssertFalse(day.hasFieldAllowance)
        XCTAssertEqual(day.kilometres, 0)
        XCTAssertEqual(day.travelMinutes, 0)
    }

    func testAnAllowanceAloneIsWorthKeeping() {
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, hasFieldAllowance: true).isBlank)
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, kilometres: 12).isBlank)
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, travelMinutes: 30).isBlank)
        XCTAssertTrue(DayRecord(date: Fixture.workingTuesday).isBlank)
    }

    func testNegativeKilometresAndTravelAreNotKept() {
        let day = DayRecord(date: Fixture.workingTuesday, kilometres: -3, travelMinutes: -10)
        XCTAssertEqual(day.kilometres, 0)
        XCTAssertEqual(day.travelMinutes, 0)
    }

    func testTheDayCarriesWhatWasRecorded() {
        let day = Fixture.calculator(settings: settings()).compute(record: workday(allowance: true, km: 84, travel: 95), on: Fixture.workingTuesday)
        XCTAssertTrue(day.hasFieldAllowance)
        XCTAssertEqual(day.kilometres, 84)
        XCTAssertEqual(day.travelMinutes, 95)
        XCTAssertEqual(day.workedMinutes, 480, "travel is only recorded unless it counts as work")
        XCTAssertEqual(day.balanceMinutes, 0)
    }

    func testTravelCountsAsWorkWhenSet() {
        let day = Fixture.calculator(settings: settings(travelCountsAsWork: true))
            .compute(record: workday(travel: 90), on: Fixture.workingTuesday)
        XCTAssertEqual(day.workedMinutes, 570)
        XCTAssertEqual(day.travelMinutes, 90)
        XCTAssertEqual(day.countedTravelMinutes, 90)
        XCTAssertEqual(day.balanceMinutes, 90)
    }

    func testTravelOnItsOwnCountsAsAWorkedDay() {
        let travelOnly = DayRecord(date: Fixture.workingTuesday, travelMinutes: 120)
        let day = Fixture.calculator(settings: settings(travelCountsAsWork: true)).compute(record: travelOnly, on: Fixture.workingTuesday)
        XCTAssertEqual(day.workedMinutes, 120)
        XCTAssertEqual(day.balanceMinutes, -360)
    }

    func testTravelIsNotRoundedWithTheShift() {
        let rounding = settings(travelCountsAsWork: true) { $0.rounding = .nearestQuarterHour }
        let record = DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16, 7), travelMinutes: 7)
        let day = Fixture.calculator(settings: rounding).compute(record: record, on: Fixture.workingTuesday)
        // 8h 7m rounds to 8h 0m; the 7 minutes of travel are added as typed.
        XCTAssertEqual(day.workedMinutes, 487)
    }

    func testSwitchedOffNothingCountsOrShowsButNothingIsLost() {
        let off = settings(travelCountsAsWork: true, enabled: false)
        let record = workday(allowance: true, km: 84, travel: 90)
        let day = Fixture.calculator(settings: off).compute(record: record, on: Fixture.workingTuesday)
        XCTAssertFalse(day.hasFieldAllowance)
        XCTAssertEqual(day.kilometres, 0)
        XCTAssertEqual(day.travelMinutes, 0)
        XCTAssertEqual(day.workedMinutes, 480)
        XCTAssertTrue(record.hasFieldAllowance, "the record keeps it for when it is switched back on")
    }

    // MARK: - A span of days

    private func summary(
        _ settings: AppSettings,
        records: [DayRecord],
        range: CalendarDateRange = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9)),
        countingThrough: CalendarDate? = nil
    ) -> AllowanceSummary {
        let days = Fixture.engine(settings: settings, calendar: calendar)
            .days(in: range, records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }), holidays: [])
        return AllowanceSummary(days: days, settings: settings, countingThrough: countingThrough)
    }

    func testAllowanceDaysTimesTheRateKilometresTimesTheRateAndTravel() {
        let s = summary(settings(), records: [
            workday(Fixture.date(2026, 8, 3), allowance: true, km: 100, travel: 60),
            workday(Fixture.date(2026, 8, 4), allowance: true, km: 37),
            workday(Fixture.date(2026, 8, 5), travel: 45)
        ])
        XCTAssertEqual(s.allowanceDays, 2)
        XCTAssertEqual(s.allowanceCents, 60_00)
        XCTAssertEqual(s.kilometres, 137)
        XCTAssertEqual(s.mileageCents, 57_54)
        XCTAssertEqual(s.travelMinutes, 105)
        XCTAssertEqual(s.totalCents, 117_54)
        XCTAssertFalse(s.isEmpty)
    }

    func testExcludedDaysAndDaysToComeAreNotCounted() {
        var excluded = workday(Fixture.date(2026, 8, 3), allowance: true, km: 10)
        excluded.isIncluded = false
        let s = summary(settings(), records: [
            excluded,
            workday(Fixture.date(2026, 8, 4), allowance: true, km: 20),
            workday(Fixture.date(2026, 8, 6), allowance: true, km: 40)
        ], countingThrough: Fixture.date(2026, 8, 5))
        XCTAssertEqual(s.allowanceDays, 1)
        XCTAssertEqual(s.kilometres, 20)
    }

    func testNothingRecordedIsEmpty() {
        XCTAssertTrue(summary(settings(), records: [workday()]).isEmpty)
        XCTAssertTrue(summary(settings(enabled: false), records: [workday(allowance: true, km: 5)]).isEmpty)
    }

    func testNoRatesStillCountsDaysAndKilometres() {
        let unpriced = settings { $0.allowance.dailyAllowanceCents = 0; $0.allowance.centsPerKilometre = 0 }
        let s = summary(unpriced, records: [workday(allowance: true, km: 12)])
        XCTAssertEqual(s.allowanceDays, 1)
        XCTAssertEqual(s.kilometres, 12)
        XCTAssertEqual(s.totalCents, 0)
    }

    // MARK: - Earnings

    private func earnings(_ settings: AppSettings, records: [DayRecord]) -> EarningsSummary? {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))
        return Fixture.engine(settings: settings, calendar: calendar).earnings(
            in: range,
            records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }),
            holidays: []
        )
    }

    private var paid: AppSettings {
        settings { $0.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 15_00), from: nil) }
    }

    func testEarningsIncludeTheAllowanceAndTheKilometresApartFromThePay() throws {
        let summary = try XCTUnwrap(earnings(paid, records: [workday(allowance: true, km: 100)]))
        XCTAssertEqual(summary.breakdown.baseCents, 120_00)
        XCTAssertEqual(summary.breakdown.allowanceCents, 30_00)
        XCTAssertEqual(summary.breakdown.mileageCents, 42_00)
        XCTAssertEqual(summary.breakdown.surchargeCents, 0, "neither is a surcharge")
        XCTAssertEqual(summary.totalCents, 192_00)
        XCTAssertEqual(summary.months.first?.totalCents, 192_00)
    }

    func testTravelThatCountsAsWorkIsPaidAsWork() throws {
        let summary = try XCTUnwrap(earnings(settings(travelCountsAsWork: true) {
            $0.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 15_00), from: nil)
        }, records: [workday(travel: 60)]))
        XCTAssertEqual(summary.breakdown.baseCents, 135_00)
    }

    func testAnAllowanceOnADayWithNoHoursStillEarns() throws {
        let travelling = DayRecord(date: Fixture.workingTuesday, hasFieldAllowance: true, kilometres: 300)
        let summary = try XCTUnwrap(earnings(paid, records: [travelling]))
        XCTAssertEqual(summary.breakdown.allowanceCents, 30_00)
        XCTAssertEqual(summary.breakdown.mileageCents, 126_00)
    }

    func testSwitchedOffTheAllowanceEarnsNothing() throws {
        var off = paid
        off.allowance.isEnabled = false
        let summary = try XCTUnwrap(earnings(off, records: [workday(allowance: true, km: 100)]))
        XCTAssertEqual(summary.breakdown.allowanceCents, 0)
        XCTAssertEqual(summary.breakdown.mileageCents, 0)
        XCTAssertEqual(summary.totalCents, 120_00)
    }
}
