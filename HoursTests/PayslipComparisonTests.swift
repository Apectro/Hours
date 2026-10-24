import XCTest
@testable import Hours

/// "Check your payslip": what the payslip says for a month beside what the
/// app worked out, a line per figure the user typed in.
final class PayslipComparisonTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let october = YearMonth(year: 2026, month: 10)

    /// 160 h worked, 6 h overtime, 16 h sick, 8 h leave, 2,345.00 earned, in
    /// 8-hour days.
    private func figures(
        overtime: Int? = 6 * 60,
        earnings: Int? = 2_345_00,
        dayMinutes: Int = 480
    ) -> PayslipFigures {
        PayslipFigures(
            workedMinutes: 160 * 60,
            overtimeMinutes: overtime,
            sickMinutes: 16 * 60,
            leaveMinutes: 8 * 60,
            earningsCents: earnings,
            dayMinutes: dayMinutes
        )
    }

    // MARK: - Lines

    func testOnlyTheFiguresTypedInAreCompared() {
        let entry = PayslipEntry(overtimeMinutes: 6 * 60)
        let comparison = PayslipComparison(entry: entry, figures: figures())
        XCTAssertEqual(comparison.lines.map(\.item), [.overtime])
        XCTAssertTrue(PayslipComparison(entry: PayslipEntry(), figures: figures()).lines.isEmpty)
    }

    func testEverythingMatching() {
        let entry = PayslipEntry(
            workedMinutes: 160 * 60,
            overtimeMinutes: 6 * 60,
            sick: .hours(16 * 60),
            leave: .hours(8 * 60),
            grossCents: 2_345_00
        )
        let comparison = PayslipComparison(entry: entry, figures: figures())
        XCTAssertEqual(comparison.lines.map(\.item), [.worked, .overtime, .sick, .leave, .gross])
        XCTAssertTrue(comparison.lines.allSatisfy { $0.status == .match })
        XCTAssertTrue(comparison.allMatch)
        XCTAssertEqual(comparison.differenceCount, 0)
        XCTAssertEqual(comparison.lines.map(\.difference), [0, 0, 0, 0, 0])
    }

    func testAPayslipShowingLessOvertime() throws {
        let comparison = PayslipComparison(entry: PayslipEntry(overtimeMinutes: 2 * 60), figures: figures())
        let line = try XCTUnwrap(comparison.lines.first)
        XCTAssertEqual(line.appValue, 6 * 60)
        XCTAssertEqual(line.payslipValue, 2 * 60)
        XCTAssertEqual(line.difference, -4 * 60, "payslip less the app")
        XCTAssertEqual(line.status, .lessOnPayslip)
        XCTAssertEqual(line.kind, .duration)
        XCTAssertFalse(comparison.allMatch)
        XCTAssertEqual(comparison.differenceCount, 1)
    }

    func testAPayslipShowingMore() throws {
        let comparison = PayslipComparison(entry: PayslipEntry(workedMinutes: 162 * 60), figures: figures())
        XCTAssertEqual(try XCTUnwrap(comparison.lines.first).status, .moreOnPayslip)
        XCTAssertEqual(try XCTUnwrap(comparison.lines.first).difference, 120)
    }

    func testWithOvertimeNotCalculatedTheLineIsNotOffered() {
        let entry = PayslipEntry(workedMinutes: 160 * 60, overtimeMinutes: 99 * 60)
        let comparison = PayslipComparison(entry: entry, figures: figures(overtime: nil))
        XCTAssertEqual(comparison.lines.map(\.item), [.worked])
        XCTAssertTrue(comparison.allMatch, "a figure that cannot be compared is not a difference")
        XCTAssertFalse(figures(overtime: nil).offers(.overtime))
        XCTAssertTrue(figures().offers(.overtime))
    }

    func testMoneyWithNoHourlyRateIsSkipped() {
        let entry = PayslipEntry(overtimeMinutes: 6 * 60, grossCents: 2_000_00)
        let comparison = PayslipComparison(entry: entry, figures: figures(earnings: nil))
        XCTAssertEqual(comparison.lines.map(\.item), [.overtime])
        XCTAssertFalse(figures(earnings: nil).offers(.gross))
    }

    func testMoneyIsComparedInCents() throws {
        let line = try XCTUnwrap(
            PayslipComparison(entry: PayslipEntry(grossCents: 2_300_00), figures: figures()).lines.first
        )
        XCTAssertEqual(line.kind, .money)
        XCTAssertEqual(line.difference, -45_00)
        XCTAssertEqual(line.status, .lessOnPayslip)
    }

    // MARK: - Days

    func testDaysAreConvertedWithTheDailyTarget() throws {
        let entry = PayslipEntry(sick: .days(200), leave: .days(150))
        let comparison = PayslipComparison(entry: entry, figures: figures())
        let sick = try XCTUnwrap(comparison.lines.first { $0.item == .sick })
        XCTAssertEqual(sick.payslipValue, 16 * 60, "2 days of 8 hours")
        XCTAssertEqual(sick.payslipHundredthDays, 200)
        XCTAssertEqual(sick.status, .match)
        let leave = try XCTUnwrap(comparison.lines.first { $0.item == .leave })
        XCTAssertEqual(leave.payslipValue, 12 * 60, "one and a half days")
        XCTAssertEqual(leave.difference, 4 * 60)
        XCTAssertEqual(leave.status, .moreOnPayslip)
    }

    func testAnUnevenDailyTargetIsUsedAsItIs() throws {
        let entry = PayslipEntry(sick: .days(200))
        let line = try XCTUnwrap(PayslipComparison(entry: entry, figures: figures(dayMinutes: 462)).lines.first)
        XCTAssertEqual(line.payslipValue, 924)
    }

    func testDaysCannotBeReadWithoutADailyTarget() {
        let entry = PayslipEntry(sick: .days(200), leave: .hours(480))
        let comparison = PayslipComparison(entry: entry, figures: figures(dayMinutes: 0))
        XCTAssertEqual(comparison.lines.map(\.item), [.leave])
    }

    // MARK: - Tolerance

    func testHoursMatchWithinAQuarterOfAnHour() {
        func status(_ payslip: Int) -> PayslipLine.Status? {
            PayslipComparison(entry: PayslipEntry(workedMinutes: payslip), figures: figures()).lines.first?.status
        }
        let app = 160 * 60
        XCTAssertEqual(status(app + 15), .match)
        XCTAssertEqual(status(app - 15), .match)
        XCTAssertEqual(status(app + 16), .moreOnPayslip)
        XCTAssertEqual(status(app - 16), .lessOnPayslip)
    }

    func testMoneyMatchesWithinOneUnit() {
        func status(_ payslip: Int) -> PayslipLine.Status? {
            PayslipComparison(entry: PayslipEntry(grossCents: payslip), figures: figures()).lines.first?.status
        }
        let app = 2_345_00
        XCTAssertEqual(status(app + 100), .match)
        XCTAssertEqual(status(app - 100), .match)
        XCTAssertEqual(status(app + 101), .moreOnPayslip)
        XCTAssertEqual(status(app - 101), .lessOnPayslip)
    }

    func testDaysUseTheHoursTolerance() {
        // 2.03 days of 8 hours is 974 minutes: 14 over.
        let near = PayslipComparison(entry: PayslipEntry(sick: .days(203)), figures: figures())
        XCTAssertEqual(near.lines.first?.status, .match)
        let far = PayslipComparison(entry: PayslipEntry(sick: .days(204)), figures: figures())
        XCTAssertEqual(far.lines.first?.status, .moreOnPayslip)
    }

    // MARK: - The app's figures

    func testTheAppsFiguresComeFromTheResolvedMonth() {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 10_00), from: nil)
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        // Thu 1 Oct: 10 h worked; Fri 2: sick; Mon 5: vacation; Tue 6: 8 h.
        let records: [DayRecord] = [
            Fixture.record(on: Fixture.date(2026, 10, 1), start: Fixture.time(7), end: Fixture.time(17)),
            Fixture.record(on: Fixture.date(2026, 10, 2), type: .sick),
            Fixture.record(on: Fixture.date(2026, 10, 5), type: .vacation),
            Fixture.record(on: Fixture.date(2026, 10, 6), start: Fixture.time(8), end: Fixture.time(16)),
        ]
        let byKey = Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) })
        let through = Fixture.date(2026, 10, 6)
        let range = october.range(in: calendar)
        let resolved = engine.resolve(in: range, records: byKey, holidays: [], countingThrough: through)
        let earnings = engine.earnings(in: range, records: byKey, holidays: [], countingThrough: through)

        let figures = PayslipFigures(
            days: resolved.days,
            summary: resolved.summary,
            earnings: earnings,
            settings: settings,
            month: october,
            calendar: calendar,
            countingThrough: through
        )
        XCTAssertEqual(figures.workedMinutes, 18 * 60)
        XCTAssertEqual(figures.overtimeMinutes, resolved.summary.overtimeMinutes)
        XCTAssertEqual(figures.overtimeMinutes, 2 * 60)
        XCTAssertEqual(figures.sickMinutes, 8 * 60)
        XCTAssertEqual(figures.leaveMinutes, 8 * 60)
        XCTAssertEqual(figures.earningsCents, earnings?.totalCents)
        XCTAssertNotNil(figures.earningsCents)
        XCTAssertEqual(figures.dayMinutes, 480)
    }

    func testOvertimeIsLeftOutWhenTheAppDoesNotCalculateIt() {
        var features = FeatureToggles()
        features.autoCalculateOvertime = false
        let off = PayslipFigures(
            days: [], summary: .empty(range: october.range(in: calendar)), earnings: nil,
            settings: Fixture.settings(features: features), month: october, calendar: calendar, countingThrough: nil
        )
        XCTAssertNil(off.overtimeMinutes)
        XCTAssertNil(off.earningsCents)

        features = FeatureToggles()
        features.trackOvertime = false
        let noBalance = PayslipFigures(
            days: [], summary: .empty(range: october.range(in: calendar)), earnings: nil,
            settings: Fixture.settings(features: features), month: october, calendar: calendar, countingThrough: nil
        )
        XCTAssertNil(noBalance.overtimeMinutes)
    }

    // MARK: - Typing

    func testHoursAreTypedAsDecimalsOrHoursAndMinutes() {
        XCTAssertEqual(PayslipInput.minutes(from: "168"), 168 * 60)
        XCTAssertEqual(PayslipInput.minutes(from: "7,5"), 450)
        XCTAssertEqual(PayslipInput.minutes(from: "7.25"), 435)
        XCTAssertEqual(PayslipInput.minutes(from: "171:30"), 171 * 60 + 30)
        XCTAssertNil(PayslipInput.minutes(from: ""))
        XCTAssertNil(PayslipInput.minutes(from: "  "))
        XCTAssertNil(PayslipInput.minutes(from: "abc"))
        XCTAssertNil(PayslipInput.minutes(from: "1:75"))
    }

    func testDaysAreTypedInHalvesOrHundredths() {
        XCTAssertEqual(PayslipInput.hundredthDays(from: "2"), 200)
        XCTAssertEqual(PayslipInput.hundredthDays(from: "1,5"), 150)
        XCTAssertEqual(PayslipInput.hundredthDays(from: "0.25"), 25)
        XCTAssertNil(PayslipInput.hundredthDays(from: ""))
        XCTAssertNil(PayslipInput.hundredthDays(from: "two"))
    }

    func testMoneyIsTypedAsOnAPayslip() {
        XCTAssertEqual(PayslipInput.cents(from: "2.345,67"), 2_345_67)
        XCTAssertEqual(PayslipInput.cents(from: "2345.6"), 2_345_60)
        XCTAssertEqual(PayslipInput.cents(from: "€ 1 200"), 1_200_00)
        XCTAssertNil(PayslipInput.cents(from: ""))
        XCTAssertNil(PayslipInput.cents(from: "—"))
    }

    func testWhatWasTypedIsShownAgainForEditing() {
        XCTAssertEqual(PayslipInput.text(minutes: 450, decimalSeparator: ","), "7,5")
        XCTAssertEqual(PayslipInput.text(minutes: 168 * 60, decimalSeparator: "."), "168")
        XCTAssertEqual(PayslipInput.text(minutes: 100, decimalSeparator: "."), "1:40")
        XCTAssertEqual(PayslipInput.text(hundredthDays: 150, decimalSeparator: ","), "1,5")
        XCTAssertEqual(PayslipInput.text(hundredthDays: 200, decimalSeparator: ","), "2")
        XCTAssertEqual(PayslipInput.text(cents: 2_345_60, decimalSeparator: ","), "2345,60")
    }

    // MARK: - Stored per month

    func testTheMonthKeyIsYearAndMonth() {
        XCTAssertEqual(october.payslipKey, "2026-10")
        XCTAssertEqual(YearMonth(year: 2027, month: 1).payslipKey, "2027-01")
    }

    func testEntriesAreKeptPerMonthAndAnEmptyOneIsRemoved() {
        var settings = AppSettings()
        XCTAssertNil(settings.payslipEntry(for: october))
        settings.setPayslipEntry(PayslipEntry(overtimeMinutes: 60), for: october)
        XCTAssertEqual(settings.payslipChecks["2026-10"], PayslipEntry(overtimeMinutes: 60))
        XCTAssertEqual(settings.payslipEntry(for: october)?.overtimeMinutes, 60)
        settings.setPayslipEntry(PayslipEntry(), for: october)
        XCTAssertTrue(settings.payslipChecks.isEmpty)
        XCTAssertEqual(settings, AppSettings(), "an emptied check leaves the settings at their defaults")
    }

    func testEntriesRoundTripThroughSettingsAndABackup() throws {
        var settings = AppSettings()
        let entry = PayslipEntry(
            workedMinutes: 9_600, overtimeMinutes: 360, sick: .days(150), leave: .hours(480), grossCents: 2_345_67
        )
        settings.setPayslipEntry(entry, for: october)

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.payslipEntry(for: october), entry)

        let archive = BackupArchive(settings: settings, days: [], holidays: [])
        let back = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(back.settings.payslipEntry(for: october), entry)
    }

    func testSettingsWithoutChecksReadAsNone() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        XCTAssertTrue(settings.payslipChecks.isEmpty)
        let json = try String(decoding: JSONEncoder().encode(AppSettings()), as: UTF8.self)
        XCTAssertFalse(json.contains("payslipChecks"), "nothing is written until a payslip is checked")
    }

    func testAnUnreadableMonthIsDroppedAndTheRestKept() throws {
        let json = #"""
        {"payslipChecks": {
            "2026-09": {"overtimeMinutes": "lots"},
            "2026-10": {"overtimeMinutes": 120, "sick": {"unit": "days", "amount": 150}, "future": true},
            "2026-11": 7
        }}
        """#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.payslipEntry(for: october), PayslipEntry(overtimeMinutes: 120, sick: .days(150)))
        XCTAssertNil(settings.payslipEntry(for: YearMonth(year: 2026, month: 9)), "a month with nothing readable is none")
        XCTAssertNil(settings.payslipEntry(for: YearMonth(year: 2026, month: 11)))

        let unknownUnit = try JSONDecoder().decode(
            PayslipEntry.self, from: Data(#"{"sick": {"unit": "weeks", "amount": 2}, "grossCents": 100}"#.utf8)
        )
        XCTAssertEqual(unknownUnit, PayslipEntry(grossCents: 100))
    }

    /// 1.0 and 1.1 decode settings with keys they know; this one is skipped.
    private struct OlderSettings: Decodable {
        var appearance: AppearancePreference
    }

    func testOlderVersionsSkipTheNewKey() throws {
        var settings = AppSettings()
        settings.appearance = .light
        settings.setPayslipEntry(PayslipEntry(overtimeMinutes: 60), for: october)
        let old = try JSONDecoder().decode(OlderSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(old.appearance, .light)
    }

    // MARK: - The text for payroll

    func testTheSummaryForPayrollListsEachLineInTheExportLanguage() {
        let entry = PayslipEntry(overtimeMinutes: 2 * 60, sick: .days(200), grossCents: 2_345_00)
        let comparison = PayslipComparison(entry: entry, figures: figures())
        let text = comparison.summaryText(
            monthTitle: "October 2026",
            language: .english,
            duration: DurationFormatting(),
            money: MoneyFormatting(currencyCode: "EUR", locale: Locale(identifier: "en_GB"))
        )
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Payslip check · October 2026")
        XCTAssertTrue(text.contains("Overtime: my records 6h · payslip 2h · difference −4h"), text)
        XCTAssertTrue(text.contains("Sick leave: my records 16h · payslip 2 × 8h = 16h · matches"), text)
        XCTAssertTrue(text.contains("Gross pay: my records €2,345.00 · payslip €2,345.00 · matches"), text)
        XCTAssertEqual(lines.last, "Could you please check this? Thank you.")
    }

    func testTheSummaryWhenEverythingMatches() {
        let comparison = PayslipComparison(entry: PayslipEntry(workedMinutes: 160 * 60), figures: figures())
        let text = comparison.summaryText(
            monthTitle: "Oktober 2026", language: .german, duration: DurationFormatting(),
            money: MoneyFormatting(currencyCode: "EUR", locale: Locale(identifier: "de_DE"))
        )
        XCTAssertEqual(
            text,
            "Kontrolle der Lohnabrechnung · Oktober 2026\nGearbeitet: meine Aufzeichnungen 160h · Lohnabrechnung 160h · stimmt"
        )
    }

    func testEveryPayslipTermIsWrittenInEveryLanguage() {
        for language in ExportLanguage.allCases where language != .device {
            for term in PayslipTerm.allCases {
                XCTAssertFalse(language(term).isEmpty, "\(term) in \(language)")
            }
        }
        XCTAssertEqual(ExportLanguage.croatian(.payslipCheck), "Provjera platne liste")
    }
}
