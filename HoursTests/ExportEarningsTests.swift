import XCTest
@testable import Hours

/// What a personal timesheet says about money: nothing, unless asked.
final class ExportEarningsTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let range = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))

    private func settings(includeEarnings: Bool, rate: Int? = 15_00) -> AppSettings {
        var settings = Fixture.settings()
        settings.export.language = .english
        settings.export.includeEarnings = includeEarnings
        if let rate { settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: rate), from: nil) }
        return settings
    }

    private func table(_ settings: AppSettings) -> ReportTable {
        let records = [
            DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16)),
            DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(12)),
        ]
        let byKey = Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first })
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let days = engine.days(in: range, records: byKey, holidays: [])
        let earnings = engine.earnings(in: range, records: byKey, holidays: [])
        return ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Week", earnings: earnings, currencyCode: "EUR")
    }

    func testATimesheetHasNoEarningsUnlessAskedFor() {
        let table = table(settings(includeEarnings: false))

        XCTAssertFalse(table.columns.contains(.earnings))
        XCTAssertFalse(table.tiles.contains { $0.label == "Earnings" })
        XCTAssertFalse(table.totals.contains { $0.label == "Earnings" })
    }

    func testAskedForTheEarningsAreAColumnATileAndATotal() throws {
        let table = table(settings(includeEarnings: true))

        let column = try XCTUnwrap(table.columns.firstIndex(of: .earnings))
        XCTAssertEqual(column, table.columns.count - 1, "after the columns chosen")
        XCTAssertEqual(table.heading(at: column), "Earnings (EUR)")
        XCTAssertEqual(table.rows.first { $0.id == Fixture.workingMonday.key }?.values[column], "120.00")
        XCTAssertEqual(table.rows.first { $0.id == Fixture.workingTuesday.key }?.values[column], "60.00")
        XCTAssertEqual(table.rows.first { $0.id == Fixture.saturday.key }?.values[column], "")
        XCTAssertEqual(table.totalRow?.values[column], "180.00")
        XCTAssertEqual(table.totals.first { $0.label == "Earnings" }?.value, "180.00 EUR")
        XCTAssertNotNil(table.tiles.first { $0.label == "Earnings" })
    }

    func testTheCellsFollowTheFilesDecimalSeparator() {
        var settings = settings(includeEarnings: true)
        settings.export.decimalSeparator = .comma
        settings.export.fieldSeparator = .semicolon

        let csv = CSVExporter.string(for: table(settings), preferences: settings.export)

        XCTAssertTrue(csv.contains(";120,00\r\n"), csv)
    }

    func testWithoutARateThereIsNothingToAdd() {
        let table = table(settings(includeEarnings: true, rate: nil))

        XCTAssertFalse(table.columns.contains(.earnings))
    }

    func testEarningsAreNeverAColumnToChoose() {
        var features = FeatureToggles()
        features.trackNotes = true

        XCTAssertFalse(features.availableColumns().contains(.earnings))
        XCTAssertFalse(settings(includeEarnings: true).effectiveExportColumns.contains(.earnings))
    }
}
