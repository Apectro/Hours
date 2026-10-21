import XCTest
@testable import Hours

/// What an export is called: its title, the period in words, and the file.
///
/// These lived in the export screen, where nothing could test them; the
/// screen now serves both your hours and a site's, so they moved here.
final class ExportNamingTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func naming(owner: String = "", language: ExportLanguage = .english) -> ExportNaming {
        ExportNaming(
            settings: Fixture.settings(export: ExportPreferences(language: language, ownerName: owner)),
            calendar: calendar
        )
    }

    func testAMonthIsNamedForTheMonth() {
        let names = naming()
        XCTAssertEqual(names.period(rangeKind: .month, anchor: august.start, range: august), "August 2026")
        XCTAssertEqual(names.reportTitle(rangeKind: .month, anchor: august.start, range: august), "Hours — August 2026")
    }

    func testAYearIsNamedForTheYear() {
        let range = CalendarDateRange.year(2026, in: calendar)
        XCTAssertEqual(naming().period(rangeKind: .year, anchor: august.start, range: range), "2026")
    }

    func testTheTitleIsInTheExportLanguage() {
        let names = naming(language: .german)
        XCTAssertEqual(names.reportTitle(rangeKind: .month, anchor: august.start, range: august), "Stunden — August 2026")
    }

    /// Led by the name, so a folder of timesheets from several people sorts
    /// by whose they are before it sorts by when.
    func testTheTimesheetFileIsLedByTheName() {
        XCTAssertEqual(naming().timesheetFileName(rangeKind: .month, range: august), "Hours 2026-08")
        XCTAssertEqual(
            naming(owner: "Ada Lovelace").timesheetFileName(rangeKind: .month, range: august),
            "Ada Lovelace - Hours 2026-08"
        )
        XCTAssertEqual(naming().timesheetFileName(rangeKind: .year, range: august), "Hours 2026")
    }

    /// The site first and then the month, so a folder of them sorts by site.
    func testTheSiteFileIsTheSiteAndTheMonth() {
        let site = Site(name: "Bau Süd")
        XCTAssertEqual(naming().siteFileName(site, month: YearMonth(year: 2026, month: 8)), "Bau Süd 2026-08")
    }
}
