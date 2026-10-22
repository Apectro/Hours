import XCTest
@testable import Hours

/// The site diary on the director's sheet: blocks for the PDF's diary pages,
/// and a sheet of its own in the workbook.
final class SiteDiaryExportTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func settings(_ language: ExportLanguage = .english) -> AppSettings {
        Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
    }

    private func diary(_ day: Int, month: Int = 8, _ fill: (inout SiteDiary) -> Void = { _ in }) -> SiteDiary {
        var diary = SiteDiary(siteID: site.id, date: Fixture.date(2026, month, day))
        fill(&diary)
        return diary
    }

    private func photo(_ day: Int, order: Int) -> DiaryPhotoReference {
        DiaryPhotoReference(id: UUID(), date: Fixture.date(2026, 8, day), sortOrder: order)
    }

    private func report(
        _ diaries: [SiteDiary],
        photos: [DiaryPhotoReference] = [],
        stops: [CalendarDate] = [],
        language: ExportLanguage = .english
    ) -> SiteDiaryReport {
        SiteDiaryReportBuilder(settings: settings(language), calendar: calendar)
            .make(diaries: diaries, photos: photos, badWeatherStops: Set(stops), range: august)
    }

    // MARK: - Blocks

    func testOneBlockPerDayWithADiaryInDateOrder() {
        let result = report([diary(12) { $0.workDone = "b" }, diary(3) { $0.workDone = "a" }])
        XCTAssertEqual(result.blocks.map(\.date), [Fixture.date(2026, 8, 3), Fixture.date(2026, 8, 12)])
    }

    func testBlankDiariesAndOtherMonthsAreLeftOut() {
        let result = report([diary(3), diary(4, month: 9) { $0.workDone = "September" }])
        XCTAssertTrue(result.isEmpty)
    }

    func testADayWithOnlyPhotosStillHasABlock() {
        let picture = photo(5, order: 0)
        let result = report([], photos: [picture])
        XCTAssertEqual(result.blocks.map(\.photoIDs), [[picture.id]])
    }

    func testPhotosAreInTheOrderTheyWereAdded() {
        let first = photo(5, order: 0)
        let second = photo(5, order: 1)
        let result = report([diary(5) { $0.workDone = "x" }], photos: [second, first])
        XCTAssertEqual(result.blocks.first?.photoIDs, [first.id, second.id])
    }

    func testABlockCarriesTheWeatherAndOnlyTheTextsThatWereWritten() {
        let result = report([diary(4) {
            $0.weather = .rain
            $0.temperatureCelsius = 7
            $0.workDone = "Formwork"
            $0.visitors = "Inspector"
        }], language: .german)
        let block = result.blocks[0]
        XCTAssertEqual(block.weatherLine, "Regen · 7 °C")
        XCTAssertEqual(block.lines.map(\.label), ["Ausgeführte Arbeiten", "Besucher"])
        XCTAssertEqual(block.lines.map(\.text), ["Formwork", "Inspector"])
        XCTAssertEqual(result.title, "Bautagebuch")
    }

    func testARainedOffDaySaysSoBesideTheWeather() {
        let result = report([diary(4) { $0.weather = .rain }], stops: [Fixture.date(2026, 8, 4)])
        XCTAssertEqual(result.blocks.first?.weatherLine, "Rain · Bad weather")
    }

    func testTheHeadingNamesTheWeekday() {
        let result = report([diary(4) { $0.workDone = "x" }])
        XCTAssertTrue(result.blocks.first?.heading.contains("Tue") == true, result.blocks.first?.heading ?? "")
    }

    // MARK: - On the sheet

    private func sheet(diary: SiteDiaryReport?) -> ReportTable {
        let settings = self.settings()
        let day = SiteDay(
            siteID: site.id, date: Fixture.date(2026, 8, 4), start: Fixture.time(7), end: Fixture.time(16),
            present: [Attendance(memberID: CrewMember.youID)]
        )
        var table = SiteSheetBuilder(settings: settings, calendar: calendar).makeTable(
            site: site, crew: [], results: [SiteDayCalculator(settings: settings, calendar: calendar).compute(day)],
            range: august
        )
        table.diary = diary
        return table
    }

    private func workbookParts(_ table: ReportTable) -> String {
        String(decoding: XLSXWriter.data(for: table, preferences: ExportPreferences()), as: UTF8.self)
    }

    func testTheWorkbookGetsADiarySheetWhenThereIsADiary() {
        let diary = report([diary(4) { $0.weather = .sunny; $0.problems = "Crane down" }])
        let parts = workbookParts(sheet(diary: diary))
        XCTAssertTrue(parts.contains("xl/worksheets/sheet2.xml"))
        XCTAssertTrue(parts.contains(#"<sheet name="Site diary" sheetId="2""#))
        XCTAssertTrue(parts.contains("Crane down"))
        XCTAssertTrue(parts.contains("Sunny"))
    }

    func testTheWorkbookStaysOneSheetWithoutADiary() {
        let parts = workbookParts(sheet(diary: report([])))
        XCTAssertFalse(parts.contains("sheet2.xml"))
        XCTAssertFalse(workbookParts(sheet(diary: nil)).contains("sheet2.xml"))
    }

    func testTheDiaryTableHasAColumnPerText() {
        let table = report([diary(4) { $0.workDone = "Formwork" }]).table(language: .english)
        XCTAssertEqual(table.columnHeadings(), ["Day", "Weather", "Work done", "Deliveries", "Problems / delays", "Visitors"])
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0].values[2], "Formwork")
    }

    /// The CSV is one table, which is what a CSV importer expects, so the
    /// diary is not appended to it.
    func testTheCSVIsTheHoursAlone() {
        let csv = String(decoding: CSVExporter.data(
            for: sheet(diary: report([diary(4) { $0.workDone = "Formwork" }])),
            preferences: ExportPreferences()
        ), as: UTF8.self)
        XCTAssertFalse(csv.contains("Formwork"))
    }
}
