import XCTest
@testable import Hours

/// A personal timesheet with field allowance, kilometres and travel: columns
/// only when a day has them, and lines in the summary, with what they come
/// to only when earnings are on the sheet.
final class AllowanceExportTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let range = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))

    private func settings(
        language: ExportLanguage = .english,
        includeEarnings: Bool = false,
        tracking: Bool = true
    ) -> AppSettings {
        var settings = Fixture.settings()
        settings.export.language = language
        settings.export.includeEarnings = includeEarnings
        settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 15_00), from: nil)
        settings.allowance = AllowancePreferences(
            isEnabled: tracking, dailyAllowanceCents: 30_00, centsPerKilometre: 42
        )
        return settings
    }

    private let withExtras = [
        DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16),
                  hasFieldAllowance: true, kilometres: 84, travelMinutes: 95),
        DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(12),
                  hasFieldAllowance: true, kilometres: 16),
    ]

    private let plain = [
        DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16)),
    ]

    private func table(_ settings: AppSettings, records: [DayRecord]) -> ReportTable {
        let byKey = Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first })
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let days = engine.days(in: range, records: byKey, holidays: [])
        let earnings = engine.earnings(in: range, records: byKey, holidays: [])
        return ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Week", earnings: earnings, currencyCode: "EUR")
    }

    private func row(_ table: ReportTable, _ date: CalendarDate) -> ReportRow? {
        table.rows.first { $0.id == date.key }
    }

    func testNoDayWithThemMeansNoColumnsAndNoLines() {
        let table = table(settings(), records: plain)
        XCTAssertFalse(table.columns.contains(.allowance))
        XCTAssertFalse(table.columns.contains(.kilometres))
        XCTAssertFalse(table.columns.contains(.travel))
        XCTAssertFalse(table.totals.contains { $0.label == "Allowance days" })
        XCTAssertFalse(table.tiles.contains { $0.label == "Allowance days" })
    }

    func testTheColumnsComeBeforeTheNotesWithEachDaysFigures() throws {
        let table = table(settings(), records: withExtras)
        let allowance = try XCTUnwrap(table.columns.firstIndex(of: .allowance))
        let km = try XCTUnwrap(table.columns.firstIndex(of: .kilometres))
        let travel = try XCTUnwrap(table.columns.firstIndex(of: .travel))
        let note = try XCTUnwrap(table.columns.firstIndex(of: .note))
        XCTAssertEqual([allowance, km, travel], [note - 3, note - 2, note - 1])
        XCTAssertEqual(table.heading(at: allowance), "Allowance")
        XCTAssertEqual(table.heading(at: km), "km")
        XCTAssertEqual(table.heading(at: travel), "Travel")

        let monday = try XCTUnwrap(row(table, Fixture.workingMonday))
        XCTAssertEqual(monday.values[allowance], "✓")
        XCTAssertEqual(monday.values[km], "84")
        XCTAssertEqual(monday.numbers[km], 84, "a number the workbook can add up")
        XCTAssertEqual(monday.values[travel], "1h 35m")
        XCTAssertEqual(monday.minutes[travel], 95)

        let tuesday = try XCTUnwrap(row(table, Fixture.workingTuesday))
        XCTAssertEqual(tuesday.values[travel], "")
        XCTAssertNil(tuesday.minutes[travel])

        XCTAssertEqual(table.totalRow?.values[km], "100")
        XCTAssertEqual(table.totalRow?.values[travel], "1h 35m")
        XCTAssertEqual(table.totalRow?.values[allowance], "2")
    }

    func testOnlyTheColumnsWithSomethingInThemAppear() {
        let kmOnly = [DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16), kilometres: 12)]
        let table = table(settings(), records: kmOnly)
        XCTAssertTrue(table.columns.contains(.kilometres))
        XCTAssertFalse(table.columns.contains(.allowance))
        XCTAssertFalse(table.columns.contains(.travel))
    }

    func testTheSummaryCountsThemWithoutMoneyUnlessEarningsAreOn() throws {
        let table = table(settings(), records: withExtras)
        XCTAssertEqual(table.totals.first { $0.label == "Allowance days" }?.value, "2")
        XCTAssertEqual(table.totals.first { $0.label == "Kilometres" }?.value, "100 km")
        XCTAssertEqual(table.totals.first { $0.label == "Travel" }?.value, "1h 35m")
        XCTAssertEqual(table.totals.first { $0.label == "Travel" }?.minutes, 95)
        XCTAssertEqual(table.tiles.first { $0.label == "Allowance days" }?.value, "2")
        XCTAssertFalse(table.totals.contains { $0.label == "Allowance" })
        XCTAssertFalse(table.totals.contains { $0.label == "Mileage" })
    }

    func testWithEarningsTheAmountsAreLabelledAndInTheTotal() throws {
        let table = table(settings(includeEarnings: true), records: withExtras)
        XCTAssertEqual(table.totals.first { $0.label == "Allowance" }?.value, "60.00 EUR")
        XCTAssertEqual(table.totals.first { $0.label == "Mileage" }?.value, "42.00 EUR")
        // 12 hours at 15.00, then the allowance and the kilometres on top.
        XCTAssertEqual(table.totals.first { $0.label == "Earnings" }?.value, "282.00 EUR")
        let earnings = try XCTUnwrap(table.columns.firstIndex(of: .earnings))
        XCTAssertEqual(row(table, Fixture.workingMonday)?.values[earnings], "185.28")
    }

    func testNotTrackedTheSheetIsAsBefore() {
        let table = table(settings(tracking: false), records: withExtras)
        XCTAssertFalse(table.columns.contains(.allowance))
        XCTAssertFalse(table.columns.contains(.kilometres))
        XCTAssertFalse(table.totals.contains { $0.label == "Allowance days" })
    }

    func testTheColumnsAreNeverOnesToChoose() {
        let features = FeatureToggles()
        for column in [ReportColumn.allowance, .kilometres, .travel] {
            XCTAssertFalse(features.availableColumns().contains(column))
        }
    }

    func testInGerman() {
        let table = table(settings(language: .german, includeEarnings: true), records: withExtras)
        XCTAssertTrue(table.columnHeadings().contains("Auslöse"))
        XCTAssertTrue(table.columnHeadings().contains("km"))
        XCTAssertTrue(table.columnHeadings().contains("Fahrzeit"))
        XCTAssertNotNil(table.totals.first { $0.label == "Auslösetage" })
        XCTAssertNotNil(table.totals.first { $0.label == "Kilometergeld" })
    }

    func testInCroatian() {
        let table = table(settings(language: .croatian), records: withExtras)
        XCTAssertTrue(table.columnHeadings().contains("Terenski dodatak"))
        XCTAssertTrue(table.columnHeadings().contains("km"))
        XCTAssertTrue(table.columnHeadings().contains("Putovanje"))
        XCTAssertEqual(table.totals.first { $0.label == "Dani terenskog dodatka" }?.value, "2")
    }

    func testTheCSVCarriesTheColumns() {
        let settings = settings()
        let csv = CSVExporter.string(for: table(settings, records: withExtras), preferences: settings.export)
        XCTAssertTrue(csv.contains("Allowance"), csv)
        XCTAssertTrue(csv.contains(",✓,84,1h 35m,"), csv)
    }
}
