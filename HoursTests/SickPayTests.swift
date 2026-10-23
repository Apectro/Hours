import XCTest
@testable import Hours

/// Paid absence at a percentage, and the Croatian rule that the employer
/// pays sick leave for the first 42 days only.
///
/// Only money changes: the balance and the hours credited are the same as at
/// 100%, which `testTheBalanceDoesNotChange` holds.
final class SickPayTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let fifteen = PayRules(hourlyRateCents: 15_00)

    private func settings(
        _ rules: PayRules? = nil,
        sick: (inout DayTypeDefinition) -> Void = { _ in }
    ) -> AppSettings {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: rules ?? fifteen, from: nil)
        var definition = DayTypeCatalog.standard.definition(for: .sick)
        sick(&definition)
        settings.customDayTypes = [definition]
        return settings
    }

    private func records(_ records: [DayRecord]) -> [Int: DayRecord] {
        Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func summary(_ settings: AppSettings, in range: CalendarDateRange, records: [DayRecord]) -> EarningsSummary? {
        Fixture.engine(settings: settings, calendar: calendar)
            .earnings(in: range, records: self.records(records), holidays: [])
    }

    private func earnings(_ settings: AppSettings, on date: CalendarDate, records: [DayRecord]) -> DayEarnings? {
        summary(settings, in: CalendarDateRange(single: date), records: records)?.days.first
    }

    /// Every calendar day from `start` for `count` days, as Sick.
    private func sickRun(from start: CalendarDate, days count: Int) -> [DayRecord] {
        (0..<count).map { DayRecord(date: start.adding(days: $0, in: calendar), dayTypeID: .sick) }
    }

    // MARK: - The definition

    func testPaidAtIsAHundredPercentByDefault() {
        for definition in DayTypeDefinition.builtIns {
            XCTAssertEqual(definition.paidPercent, 100, "\(definition.id.rawValue)")
            XCTAssertFalse(definition.employerPaysFirst42Days, "\(definition.id.rawValue)")
        }
    }

    /// A day type stored before the fields existed reads as paid in full.
    func testADayTypeStoredBeforePaidAtReadsAsAHundredPercent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Sonderurlaub","symbolName":"star","tint":"blue",
         "expectation":"creditedAbsence","showsTimesByDefault":false,"isBuiltIn":false,"sortOrder":500}
        """
        let decoded = try JSONDecoder().decode(DayTypeDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.name, "Sonderurlaub")
        XCTAssertEqual(decoded.expectation, .creditedAbsence)
        XCTAssertEqual(decoded.paidPercent, 100)
        XCTAssertFalse(decoded.employerPaysFirst42Days)
    }

    func testPaidAtRoundTripsAndIsKeptBetweenNoneAndAll() throws {
        var definition = DayTypeCatalog.standard.definition(for: .sick)
        definition.paidPercent = 70
        definition.employerPaysFirst42Days = true
        let decoded = try JSONDecoder().decode(DayTypeDefinition.self, from: JSONEncoder().encode(definition))
        XCTAssertEqual(decoded, definition)

        let wild = #"{"id":"sick","name":"Sick leave","symbolName":"x","tint":"red","expectation":"creditedAbsence","showsTimesByDefault":false,"isBuiltIn":true,"sortOrder":40,"paidPercent":250}"#
        XCTAssertEqual(try JSONDecoder().decode(DayTypeDefinition.self, from: Data(wild.utf8)).paidPercent, 100)
        let negative = wild.replacingOccurrences(of: "250", with: "-5")
        XCTAssertEqual(try JSONDecoder().decode(DayTypeDefinition.self, from: Data(negative.utf8)).paidPercent, 0)
    }

    /// The decoder 1.0 and earlier 1.1 builds have: Swift's own, from the
    /// stored properties of the time. It must still read a new definition.
    private struct OlderDefinition: Codable {
        var id: DayTypeID
        var name: String
        var symbolName: String
        var tint: TypeTint
        var expectation: ExpectationPolicy
        var showsTimesByDefault: Bool
        var isBuiltIn: Bool
        var sortOrder: Int
    }

    func testAnOlderAppStillReadsADefinitionWithPaidAt() throws {
        var definition = DayTypeCatalog.standard.definition(for: .sick)
        definition.paidPercent = 70
        definition.employerPaysFirst42Days = true
        let older = try JSONDecoder().decode(OlderDefinition.self, from: JSONEncoder().encode(definition))
        XCTAssertEqual(older.id, .sick)
        XCTAssertEqual(older.expectation, .creditedAbsence)
    }

    /// A whole settings blob with an older custom type in it keeps the type.
    func testSettingsWithAnOlderCustomTypeKeepIt() throws {
        var settings = AppSettings()
        settings.customDayTypes = [DayTypeDefinition(
            id: DayTypeID(UUID().uuidString), name: "Training", symbolName: "book", tint: .green,
            expectation: .creditedAbsence, showsTimesByDefault: false
        )]
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var types = try XCTUnwrap(object["customDayTypes"] as? [[String: Any]])
        types[0].removeValue(forKey: "paidPercent")
        types[0].removeValue(forKey: "employerPaysFirst42Days")
        object["customDayTypes"] = types
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.customDayTypes.map(\.name), ["Training"])
        XCTAssertEqual(decoded.customDayTypes.first?.paidPercent, 100)
    }

    // MARK: - The money

    func testASickDayAtSeventyPercentEarnsSeventyPercentOfItsCreditedHours() {
        let settings = settings { $0.paidPercent = 70 }
        let result = earnings(settings, on: Fixture.workingTuesday, records: [
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        ])
        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 84_00, "8h at 15.00 is 120.00; 70% is 84.00")
        XCTAssertEqual(result?.totalCents, 84_00)
        XCTAssertEqual(result?.absencePaidPercent, 70)
        XCTAssertFalse(result?.isPaidByHealthInsurance ?? true)
    }

    func testAHundredPercentDayIsNotMarkedReduced() {
        let result = earnings(settings(), on: Fixture.workingTuesday, records: [
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        ])
        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 120_00)
        XCTAssertNil(result?.absencePaidPercent)
    }

    func testNoPercentOnlyAppliesToTheTypeItIsSetOn() {
        let settings = settings { $0.paidPercent = 70 }
        let result = earnings(settings, on: Fixture.workingTuesday, records: [
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        ])
        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 120_00)
    }

    func testZeroPercentEarnsNothing() {
        let settings = settings { $0.paidPercent = 0 }
        let result = earnings(settings, on: Fixture.workingTuesday, records: [
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        ])
        XCTAssertEqual(result?.totalCents, 0)
    }

    /// Hours worked on a reduced day are still paid in full; only the
    /// credited hours take the percentage.
    func testWorkOnTheDayIsStillPaidInFull() {
        var custom = DayTypeCatalog.standard.definition(for: .holiday)
        custom.paidPercent = 50
        var settings = settings()
        settings.customDayTypes.append(custom)
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .holiday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(10))]
        )
        let result = earnings(settings, on: Fixture.workingTuesday, records: [record])
        XCTAssertEqual(result?.breakdown.paidAbsenceCents, 60_00)
        XCTAssertEqual(result?.breakdown.baseCents, 30_00)
    }

    func testTheSwitchForPaidDaysOffStillWins() {
        var rules = fifteen
        rules.paidAbsenceEarns = false
        let settings = settings(rules) { $0.paidPercent = 70 }
        let result = earnings(settings, on: Fixture.workingTuesday, records: [
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        ])
        XCTAssertEqual(result?.totalCents, 0)
    }

    func testTheBalanceDoesNotChange() {
        let reduced = settings { $0.paidPercent = 70 }
        let full = settings()
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        let range = CalendarDateRange(single: Fixture.workingTuesday)
        let a = Fixture.engine(settings: reduced, calendar: calendar).summary(in: range, records: records([record]), holidays: [])
        let b = Fixture.engine(settings: full, calendar: calendar).summary(in: range, records: records([record]), holidays: [])
        XCTAssertEqual(a, b)
    }

    // MARK: - The first 42 days

    private var croatianSick: AppSettings {
        settings {
            $0.paidPercent = 70
            $0.employerPaysFirst42Days = true
        }
    }

    /// 1 September 2026 is a Tuesday; the 42nd calendar day of a run from
    /// it is 12 October, the 43rd 13 October (both working days).
    func testTheFortySecondDayIsPaidAndTheFortyThirdIsNot() {
        let run = sickRun(from: Fixture.date(2026, 9, 1), days: 50)
        let day42 = earnings(croatianSick, on: Fixture.date(2026, 10, 12), records: run)
        let day43 = earnings(croatianSick, on: Fixture.date(2026, 10, 13), records: run)

        XCTAssertEqual(day42?.totalCents, 84_00)
        XCTAssertFalse(day42?.isPaidByHealthInsurance ?? true)
        XCTAssertEqual(day43?.totalCents, 0)
        XCTAssertEqual(day43?.isPaidByHealthInsurance, true)
    }

    /// October's figures know September's sick days, though only October
    /// was asked for.
    func testARunCarriesAcrossMonths() throws {
        let run = sickRun(from: Fixture.date(2026, 9, 1), days: 50)
        let october = CalendarDateRange(start: Fixture.date(2026, 10, 1), end: Fixture.date(2026, 10, 31))
        let engine = Fixture.engine(settings: croatianSick, calendar: calendar)
        let fetched = engine.earningsRange(covering: october)
        XCTAssertLessThanOrEqual(fetched.start, Fixture.date(2026, 9, 1).adding(days: 1, in: calendar),
                                 "the range to fetch reaches back far enough to see the run")
        let summary = try XCTUnwrap(engine.earnings(
            in: october,
            records: records(run.filter { fetched.contains($0.date) }),
            holidays: []
        ))
        // 1–12 October are days 31–42: the working days among them earn.
        // 1 Oct Thu, 2 Fri, 5–9, 12 → 8 working days at 84.00.
        XCTAssertEqual(summary.totalCents, 8 * 84_00)
        // 13–20 October, days 43–50: paid by the health insurer.
        XCTAssertEqual(summary.healthInsuranceDays, 8)
    }

    func testAGapStartsANewRun() {
        // 41 days sick, a working day at work, then sick again: the count
        // starts over, so the 43rd day after the first start is still paid.
        var records = sickRun(from: Fixture.date(2026, 9, 1), days: 41)
        records.append(DayRecord(
            date: Fixture.date(2026, 10, 12),
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(16))]
        ))
        records += sickRun(from: Fixture.date(2026, 10, 13), days: 10)
        let result = earnings(croatianSick, on: Fixture.date(2026, 10, 13), records: records)
        XCTAssertEqual(result?.totalCents, 84_00)
        XCTAssertFalse(result?.isPaidByHealthInsurance ?? true)
    }

    /// A weekend left as it is, between two sick weeks, is inside the run:
    /// sick leave counts calendar days.
    func testAWeekendInsideTheRunCountsAsCalendarDays() {
        // Sick on working days only, from Tuesday 1 September; weekends
        // are not written, so they read as Weekend.
        var records: [DayRecord] = []
        for offset in 0..<50 {
            let date = Fixture.date(2026, 9, 1).adding(days: offset, in: calendar)
            let weekday = date.weekday(in: calendar)
            if weekday != 1 && weekday != 7 { records.append(DayRecord(date: date, dayTypeID: .sick)) }
        }
        XCTAssertEqual(earnings(croatianSick, on: Fixture.date(2026, 10, 12), records: records)?.totalCents, 84_00)
        XCTAssertEqual(earnings(croatianSick, on: Fixture.date(2026, 10, 13), records: records)?.totalCents, 0)
    }

    func testWithoutTheRuleTheEmployerKeepsPaying() {
        let settings = settings { $0.paidPercent = 70 }
        let run = sickRun(from: Fixture.date(2026, 9, 1), days: 50)
        let result = earnings(settings, on: Fixture.date(2026, 10, 13), records: run)
        XCTAssertEqual(result?.totalCents, 84_00)
        XCTAssertFalse(result?.isPaidByHealthInsurance ?? true)
    }

    func testWithoutTheRuleTheFetchedRangeIsTheWholeWeeks() {
        let engine = Fixture.engine(settings: settings(), calendar: calendar)
        let october = CalendarDateRange(start: Fixture.date(2026, 10, 1), end: Fixture.date(2026, 10, 31))
        XCTAssertEqual(engine.earningsRange(covering: october).start, Fixture.date(2026, 9, 28))
    }

    func testTheSummaryNamesTheReducedPercentages() throws {
        let settings = settings { $0.paidPercent = 70 }
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 7))
        let summary = try XCTUnwrap(summary(settings, in: range, records: [
            DayRecord(date: Fixture.date(2026, 8, 4), dayTypeID: .sick),
            DayRecord(date: Fixture.date(2026, 8, 5), dayTypeID: .vacation)
        ]))
        XCTAssertEqual(summary.reducedAbsencePercents, [70])
        XCTAssertEqual(summary.healthInsuranceDays, 0)
    }

    // MARK: - Croatia's default

    func testCroatiaSetsSickToSeventyPercentAndTheFirstFortyTwoDays() {
        var settings = AppSettings()
        SickPay.applyCountryDefault(.hr, to: &settings)
        let sick = settings.dayTypeCatalog.definition(for: .sick)
        XCTAssertEqual(sick.paidPercent, 70)
        XCTAssertTrue(sick.employerPaysFirst42Days)
        XCTAssertEqual(sick.name, "Sick leave", "still the shipped name, so it is still translated")
    }

    func testAnotherCountryChangesNothing() {
        for country in HolidayCountry.allCases where country != .hr {
            var settings = AppSettings()
            SickPay.applyCountryDefault(country, to: &settings)
            XCTAssertEqual(settings, AppSettings(), "\(country)")
        }
        var settings = AppSettings()
        SickPay.applyCountryDefault(nil, to: &settings)
        XCTAssertEqual(settings, AppSettings())
    }

    /// Never over a value the person set: an edited Sick type stays as it is.
    func testCroatiaLeavesAnEditedSickTypeAlone() {
        var settings = AppSettings()
        var mine = DayTypeCatalog.standard.definition(for: .sick)
        mine.paidPercent = 100
        mine.tint = .orange
        settings.customDayTypes = [mine]
        SickPay.applyCountryDefault(.hr, to: &settings)
        XCTAssertEqual(settings.customDayTypes, [mine])
    }
}
