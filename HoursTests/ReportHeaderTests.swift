import XCTest
@testable import Hours

/// What a printed timesheet says before and after its rows: the eyebrow, whose
/// hours they are, the four figures at the top, the ruled total and the lines
/// to sign on. The renderers draw these; the builder decides them, so they are
/// asserted here, on Linux, rather than only ever looked at in a capture.
final class ReportHeaderTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 7))

    /// Monday 8h, Tuesday 9h 30m, Wednesday on vacation, Thursday and Friday
    /// empty: a week that ends 14h 30m short, which is the case a red tile
    /// is for.
    private func table(
        owner: String = "Ada Lovelace",
        features: FeatureToggles = FeatureToggles(),
        language: ExportLanguage = .english
    ) -> ReportTable {
        let settings = Fixture.settings(
            features: features,
            export: ExportPreferences(language: language, ownerName: owner)
        )
        let records: [Int: DayRecord] = [
            Fixture.workingMonday.key: DayRecord(
                date: Fixture.workingMonday,
                start: Fixture.time(8),
                end: Fixture.time(16, 30),
                breaks: [.duration(30)]
            ),
            Fixture.workingTuesday.key: DayRecord(
                date: Fixture.workingTuesday,
                start: Fixture.time(8),
                end: Fixture.time(18),
                breaks: [.duration(30)]
            ),
            Fixture.date(2026, 8, 5).key: DayRecord(date: Fixture.date(2026, 8, 5), dayTypeID: .vacation)
        ]
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
            .days(in: range, records: records, holidays: [])
        return ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(
                days: days,
                range: range,
                title: "Hours — August 2026",
                period: "August 2026",
                countingThrough: range.end
            )
    }

    private func row(_ table: ReportTable, _ day: Int) -> ReportRow? {
        table.rows.first { $0.id == Fixture.date(2026, 8, day).key }
    }

    // MARK: - The header block

    func testATimesheetIsHeadedByWhoseHoursTheyAre() {
        let t = table()
        XCTAssertEqual(t.kind, .timesheet)
        XCTAssertEqual(t.eyebrow, "Timesheet")
        XCTAssertEqual(t.headline, "Ada Lovelace")
        XCTAssertEqual(t.byline, "August 2026 · 2026-08-01 – 2026-08-07")
        XCTAssertTrue(t.columnGroups.isEmpty)
        XCTAssertEqual(t.legend, "")
    }

    /// Without a name the report's own title is the headline, and the period
    /// is not said twice underneath it.
    func testWithoutANameTheTitleIsTheHeadline() {
        let t = table(owner: "")
        XCTAssertEqual(t.headline, "Hours — August 2026")
        XCTAssertEqual(t.byline, "2026-08-01 – 2026-08-07")
    }

    func testTheFourTilesAreWorkedExpectedBalanceAndDaysWorked() {
        let t = table()
        XCTAssertEqual(t.tiles.map(\.label), ["Worked", "Expected", "Balance", "Days worked"])
        XCTAssertEqual(t.tiles.map(\.value), ["17h 30m", "40h", "-14h 30m", "2"])
        XCTAssertEqual(t.tiles.map(\.isNegative), [false, false, true, false])
    }

    /// A tile for a figure the person does not track would be a zero that
    /// means nothing.
    func testTilesFollowTheFeatureToggles() {
        var features = FeatureToggles()
        features.trackExpectedHours = false
        XCTAssertEqual(table(features: features).tiles.map(\.label), ["Worked", "Days worked"])
    }

    func testTheTilesSpeakTheExportLanguage() {
        XCTAssertEqual(
            table(language: .german).tiles.map(\.label),
            ["Gearbeitet", "Soll", "Saldo", "Arbeitstage"]
        )
        XCTAssertEqual(table(language: .german).eyebrow, "Stundenzettel")
    }

    // MARK: - The rows

    /// Paid absence reads differently from a weekend: one is a day the person
    /// was owed and paid, the other a day nobody expected anything of.
    func testAbsenceDaysAreMarkedAndWeekendsAreNot() {
        let t = table()
        XCTAssertEqual(row(t, 5)?.isAbsence, true)
        XCTAssertEqual(row(t, 3)?.isAbsence, false)
        XCTAssertEqual(row(t, 1)?.isAbsence, false)
        XCTAssertEqual(row(t, 1)?.isWorkingDay, false)
        XCTAssertEqual(row(t, 3)?.role, .day)
    }

    /// The ruled total under the rows agrees with the tiles above them, so
    /// the page never shows two different answers to one question.
    func testTheTotalRowAgreesWithTheSummary() throws {
        let t = table()
        let total = try XCTUnwrap(t.totalRow)
        let index = { (column: ReportColumn) -> Int in t.columns.firstIndex(of: column) ?? 0 }
        XCTAssertEqual(total.role, .total)
        XCTAssertEqual(total.values.count, t.columns.count)
        XCTAssertEqual(total.values[0], "Total")
        XCTAssertEqual(total.values[index(.worked)], "17h 30m")
        XCTAssertEqual(total.minutes[index(.worked)], 1050)
        XCTAssertEqual(total.values[index(.expected)], "40h")
        XCTAssertEqual(total.values[index(.breakTime)], "1h")
        XCTAssertEqual(total.values[index(.note)], "")
        XCTAssertNil(total.minutes[index(.note)])
    }

    func testATimesheetIsSignedByBothSides() {
        XCTAssertEqual(table().signatures, ["Employee · date, signature", "Employer · date, signature"])
    }

    // MARK: - Counted words

    func testCountsAgreeWithTheirNounInEveryKindOfPlural() {
        XCTAssertEqual(ExportLanguage.english.people(1), "1 person")
        XCTAssertEqual(ExportLanguage.english.people(5), "5 people")
        XCTAssertEqual(ExportLanguage.english.daysOnSite(1), "1 day on site")
        XCTAssertEqual(ExportLanguage.english.daysOnSite(21), "21 days on site")

        // Croatian: one, few, and everything else.
        XCTAssertEqual(ExportLanguage.croatian.people(1), "1 osoba")
        XCTAssertEqual(ExportLanguage.croatian.people(2), "2 osobe")
        XCTAssertEqual(ExportLanguage.croatian.people(5), "5 osoba")
        XCTAssertEqual(ExportLanguage.croatian.people(12), "12 osoba")
        XCTAssertEqual(ExportLanguage.croatian.people(22), "22 osobe")
        XCTAssertEqual(ExportLanguage.croatian.daysOnSite(21), "21 dan na gradilištu")

        // Slovenian has a dual.
        XCTAssertEqual(ExportLanguage.slovenian.people(2), "2 osebi")
        XCTAssertEqual(ExportLanguage.slovenian.people(3), "3 osebe")
        XCTAssertEqual(ExportLanguage.slovenian.people(5), "5 oseb")
        XCTAssertEqual(ExportLanguage.slovenian.people(101), "101 oseba")

        // Polish: few and many.
        XCTAssertEqual(ExportLanguage.polish.people(1), "1 osoba")
        XCTAssertEqual(ExportLanguage.polish.people(3), "3 osoby")
        XCTAssertEqual(ExportLanguage.polish.people(5), "5 osób")
        XCTAssertEqual(ExportLanguage.polish.people(13), "13 osób")
        XCTAssertEqual(ExportLanguage.polish.daysOnSite(1), "1 dzień na budowie")
        XCTAssertEqual(ExportLanguage.polish.daysOnSite(2), "2 dni na budowie")

        // French counts zero with one.
        XCTAssertEqual(ExportLanguage.french.people(0), "0 personne")
        XCTAssertEqual(ExportLanguage.german.people(2), "2 Personen")
    }

    func testEveryLanguageCountsSomethingForEveryNumber() {
        for language in ExportLanguage.allCases where language != .device {
            for count in [0, 1, 2, 3, 5, 11, 12, 21, 22, 25, 101, 112] {
                XCTAssertTrue(language.people(count).hasPrefix("\(count) "), "\(language.rawValue) \(count)")
                XCTAssertGreaterThan(language.daysOnSite(count).count, "\(count) ".count + 2)
            }
        }
    }

    func testThePageFooterNamesThePageAndTheCount() {
        XCTAssertEqual(ExportLanguage.english.pageOf(1, 2), "page 1 of 2")
        XCTAssertEqual(ExportLanguage.german.pageOf(3, 4), "Seite 3 von 4")
    }
}
