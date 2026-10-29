import XCTest
@testable import Hours

/// The personal timesheet for a period worked on more than one site: a Site
/// column, a split day as a row per site with a "Day" subtotal, a "By site"
/// block, the sites in the eyebrow, and a filter to one site.
final class TwoSiteExportTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let haupt = UUID()
    private let trg = UUID()
    private let monday = Fixture.workingMonday
    private let tuesday = Fixture.workingTuesday
    private var wednesday: CalendarDate { CalendarDate(year: 2026, month: 8, day: 5) }
    private let range = CalendarDateRange(start: CalendarDate(year: 2026, month: 8, day: 3), end: CalendarDate(year: 2026, month: 8, day: 7))

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func siteShift(_ site: UUID, _ start: TimeOfDay, _ end: TimeOfDay, breakMinutes: Int = 0) -> Shift {
        Shift(
            id: site,
            start: start,
            end: end,
            breaks: breakMinutes > 0 ? [BreakSpan(id: site, explicitMinutes: breakMinutes)] : [],
            siteID: site
        )
    }

    private func records(twoSites: Bool = true) -> [DayRecord] {
        var tuesdayShifts = [siteShift(haupt, time(7), time(11, 30))]
        if twoSites { tuesdayShifts.append(siteShift(trg, time(12), time(16), breakMinutes: 30)) }
        return [
            DayRecord(date: monday, shifts: [siteShift(haupt, time(7), time(16), breakMinutes: 30)]),
            DayRecord(date: tuesday, shifts: tuesdayShifts),
            DayRecord(date: wednesday, shifts: [siteShift(twoSites ? trg : haupt, time(7), time(15), breakMinutes: 30)])
        ]
    }

    private func table(
        settings: AppSettings = Fixture.settings(),
        twoSites: Bool = true,
        filter: UUID? = nil
    ) -> ReportTable {
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
            .days(in: range, records: Dictionary(uniqueKeysWithValues: records(twoSites: twoSites).map { ($0.date.key, $0) }), holidays: [])
        var builder = ReportBuilder(settings: settings, calendar: calendar)
        builder.siteNames = [haupt: "Hauptstraße 12", trg: "Trg Pravde"]
        builder.siteAddresses = [haupt: "Hauptstraße 12\n10115 Berlin", trg: "Trg pravde 2, 10000 Zagreb"]
        builder.siteFilter = filter
        return builder.makeTable(days: days, range: range, title: "Hours — August 2026", countingThrough: wednesday)
    }

    private func column(_ table: ReportTable, _ column: ReportColumn) -> Int? {
        table.columns.firstIndex(of: column)
    }

    private func rows(of table: ReportTable, on date: CalendarDate) -> [ReportRow] {
        let dateText = ReportBuilder(settings: Fixture.settings(), calendar: calendar).dateText(date)
        guard let start = table.rows.firstIndex(where: { $0.values.first == dateText }) else { return [] }
        var result = [table.rows[start]]
        var next = start + 1
        while next < table.rows.count, table.rows[next].values.first == "" { result.append(table.rows[next]); next += 1 }
        return result
    }

    // MARK: - Columns and rows

    func testTwoSitesAddASiteColumnAfterTheDay() {
        let table = table()
        XCTAssertEqual(column(table, .site), (column(table, .weekday) ?? -1) + 1)
        XCTAssertEqual(table.columnHeadings()[column(table, .site)!], "Site")
    }

    func testOneSiteHasNoSiteColumnAndPrintsAsBefore() {
        let table = table(twoSites: false)
        XCTAssertNil(column(table, .site))
        XCTAssertTrue(table.bySite.isEmpty)
        XCTAssertTrue(table.rows.allSatisfy { $0.splitDay == nil })
        XCTAssertEqual(table.eyebrow, "Timesheet")
    }

    func testADayOnOneSiteIsOneRowNamingIt() {
        let table = table()
        let monday = rows(of: table, on: monday)
        XCTAssertEqual(monday.count, 1)
        XCTAssertEqual(monday[0].values[column(table, .site)!], "Hauptstraße 12")
        XCTAssertNil(monday[0].splitDay)
    }

    func testASplitDayIsARowPerSiteUnderOneDateThenTheDay() throws {
        let table = table()
        let tuesday = rows(of: table, on: tuesday)
        let site = try XCTUnwrap(column(table, .site))
        let worked = try XCTUnwrap(column(table, .worked))
        let breakTime = try XCTUnwrap(column(table, .breakTime))
        let start = try XCTUnwrap(column(table, .start))
        let weekday = try XCTUnwrap(column(table, .weekday))

        XCTAssertEqual(tuesday.count, 3)
        XCTAssertEqual(tuesday.map(\.splitDay), [.site, .site, .subtotal])
        XCTAssertEqual(tuesday.map { $0.values[site] }, ["Hauptstraße 12", "Trg Pravde", "Day"])
        XCTAssertEqual(tuesday[0].values[weekday], "Tue", "the date and day on the first row only")
        XCTAssertEqual(tuesday[1].values[weekday], "")
        XCTAssertEqual(tuesday.map { $0.values[start] }, ["07:00", "12:00", ""])
        XCTAssertEqual(tuesday.map { $0.minutes[worked] }, [270, 210, nil], "a workbook's sum counts the sites, not the day too")
        XCTAssertEqual(tuesday[2].values[worked], ReportBuilder(settings: Fixture.settings(), calendar: calendar).duration.string(480))
        XCTAssertEqual(tuesday.map { $0.minutes[breakTime] }, [nil, 30, nil])
        let expected = try XCTUnwrap(column(table, .expected))
        XCTAssertEqual(tuesday.map { $0.minutes[expected] }, [nil, nil, 480], "the day's own figures on the day's row")
        XCTAssertEqual(Set(tuesday.map(\.id)).count, 3, "ids stay unique")
    }

    func testTotalsCountTheSplitDayOnce() throws {
        let table = table()
        let worked = try XCTUnwrap(column(table, .worked))
        XCTAssertEqual(table.totalRow?.minutes[worked], 510 + 480 + 450)
        XCTAssertEqual(table.totals.first?.minutes, 510 + 480 + 450)
        XCTAssertEqual(table.totals.first { $0.label == "Days worked" }?.count, 3)
    }

    func testTheSubtotalSaysDayInTheExportLanguage() throws {
        var settings = Fixture.settings()
        settings.export.language = .german
        let table = table(settings: settings)
        let site = try XCTUnwrap(column(table, .site))
        XCTAssertTrue(table.rows.contains { $0.splitDay == .subtotal && $0.values[site] == "Tag" })
        XCTAssertEqual(table.columnHeadings()[site], "Baustelle")
    }

    // MARK: - By site, the tile and the eyebrow

    func testBySiteNamesEachSiteWithItsAddressAndHours() {
        let table = table()
        XCTAssertEqual(table.bySite.map(\.name), ["Hauptstraße 12", "Trg Pravde"], "in the order first worked")
        XCTAssertEqual(table.bySite.map(\.address), ["Hauptstraße 12, 10115 Berlin", "Trg pravde 2, 10000 Zagreb"])
        XCTAssertEqual(table.bySite.map(\.minutes), [510 + 270, 210 + 450])
    }

    func testASitesTileIsAddedWhileTheRowHasRoom() {
        let table = table()
        XCTAssertEqual(table.tiles.first { $0.label == "Sites" }?.value, "2")
        XCTAssertEqual(table.tiles[1].label, "Sites", "beside Worked")
        XCTAssertLessThanOrEqual(table.tiles.count, ReportBuilder.maximumTiles)
    }

    func testNoSitesTileWhenTheRowIsFull() {
        let full = (0..<ReportBuilder.maximumTiles).map { ReportTile(label: "T\($0)", value: "1") }
        XCTAssertEqual(ReportBuilder.addingSitesTile(2, to: full, language: .english), full)
        let room = Array(full.prefix(4))
        XCTAssertEqual(ReportBuilder.addingSitesTile(2, to: room, language: .english).count, 5)
    }

    func testTheEyebrowNamesTheSites() {
        XCTAssertEqual(table().eyebrow, "Timesheet · Hauptstraße 12 · Trg Pravde")
        XCTAssertEqual(table().title, "Hours — August 2026 — Hauptstraße 12 · Trg Pravde")
        var settings = Fixture.settings()
        settings.export.language = .croatian
        XCTAssertEqual(table(settings: settings).eyebrow, "Evidencija radnog vremena · Hauptstraße 12 · Trg Pravde")
    }

    func testMoreThanThreeSitesNameTheFirstTwoAndHowManyMore() {
        let extra = [UUID(), UUID()]
        let records = records() + [
            DayRecord(date: CalendarDate(year: 2026, month: 8, day: 6), shifts: [siteShift(extra[0], time(7), time(15))]),
            DayRecord(date: CalendarDate(year: 2026, month: 8, day: 7), shifts: [siteShift(extra[1], time(7), time(15))])
        ]
        for (language, expected) in [
            (ExportLanguage.german, "Stundenzettel · Hauptstraße 12 · Trg Pravde +2 weitere"),
            (.croatian, "Evidencija radnog vremena · Hauptstraße 12 · Trg Pravde + još 2")
        ] {
            var settings = Fixture.settings()
            settings.export.language = language
            let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
                .days(in: range, records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }), holidays: [])
            var builder = ReportBuilder(settings: settings, calendar: calendar)
            builder.siteNames = [haupt: "Hauptstraße 12", trg: "Trg Pravde", extra[0]: "Solarka", extra[1]: "Jarun"]
            let table = builder.makeTable(days: days, range: range, title: "Stunden")
            XCTAssertEqual(table.eyebrow, expected)
            XCTAssertEqual(table.bySite.count, 4, "the block still lists every site")
        }
    }

    // MARK: - One site only

    func testFilteringToOneSiteKeepsOnlyItsHours() throws {
        let table = table(filter: trg)
        let worked = try XCTUnwrap(column(table, .worked))

        XCTAssertNil(column(table, .site), "one site needs no column")
        XCTAssertNil(column(table, .expected), "a site's hours owe nothing on their own")
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows.map { $0.minutes[worked] }, [210, 450])
        XCTAssertEqual(table.totals.first?.minutes, 660)
        XCTAssertEqual(table.eyebrow, "Timesheet · Trg Pravde")
        XCTAssertEqual(table.title, "Hours — August 2026 — Trg Pravde")
        XCTAssertEqual(table.address, "Trg pravde 2, 10000 Zagreb")
        XCTAssertTrue(table.bySite.isEmpty)
        XCTAssertFalse(table.tiles.contains { $0.label == "Balance" })
    }

    func testTheSitesInARangeAreListedInTheOrderWorked() {
        let days = PeriodEngine(settings: Fixture.settings(), calendar: calendar, firstRecorded: Fixture.longAgo)
            .days(in: range, records: Dictionary(uniqueKeysWithValues: records().map { ($0.date.key, $0) }), holidays: [])
        XCTAssertEqual(ReportBuilder.siteIDs(in: days), [haupt, trg])
    }

    // MARK: - Files

    func testTheCSVListsTheSitesUnderTheSummary() {
        var preferences = ExportPreferences()
        preferences.includeSummaryRows = true
        let csv = CSVExporter.string(for: table(), preferences: preferences)
        XCTAssertTrue(csv.contains("By site"))
        XCTAssertTrue(csv.contains("Trg Pravde"))
    }

    func testTheWorkbookStillOpens() {
        let data = XLSXWriter.data(for: table(), preferences: ExportPreferences())
        XCTAssertFalse(data.isEmpty)
    }
}

/// The site sheets and a crew member's sheet read site days, which a move
/// already splits: each site gets only its own hours.
final class MovedDaySheetTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let date = Fixture.workingTuesday
    private let here = Site(name: "Hauptstraße 12")
    private let there = Site(name: "Trg Pravde")

    private func moved() throws -> (SiteMoveOutcome, CrewMember) {
        let ivan = CrewMember(siteID: here.id, name: "Ivan")
        let source = SiteDay(
            siteID: here.id, date: date, start: Fixture.time(7), end: Fixture.time(16), breakMinutes: 30,
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan.id)]
        )
        let outcome = try SiteMoving.apply(SiteMoveRequest(
            source: source, target: nil, targetSite: there, sourceCrew: [ivan], targetCrew: [],
            memberIDs: [ivan.id], left: Fixture.time(11, 30), started: Fixture.time(12),
            breakPlacement: .there, lock: .unlocked, tracksAllowance: false
        ))
        return (outcome, ivan)
    }

    func testEachSiteSheetHasOnlyItsOwnHours() throws {
        let (outcome, ivan) = try moved()
        let settings = Fixture.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let month = date.yearMonth.range(in: calendar)

        let hereResult = calculator.compute(outcome.source)
        XCTAssertEqual(hereResult.people.first { $0.memberID == ivan.id }?.workedMinutes, 270)
        let thereMember = try XCTUnwrap(outcome.crewChanges.first)
        let thereResult = calculator.compute(outcome.target)
        XCTAssertEqual(thereResult.people.map(\.workedMinutes), [210])

        let hereSheet = SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(site: here, crew: [ivan], results: [hereResult], range: month)
        let thereSheet = SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(site: there, crew: [thereMember], results: [thereResult], range: month)
        let duration = ReportBuilder(settings: settings, calendar: calendar).duration
        XCTAssertTrue(hereSheet.rows.contains { $0.values.contains(duration.string(270)) })
        XCTAssertFalse(hereSheet.rows.contains { $0.values.contains(duration.string(210)) })
        XCTAssertTrue(thereSheet.rows.contains { $0.values.contains(duration.string(210)) })
    }

    func testACrewMembersSheetListsBothSitesThatDay() throws {
        let (outcome, ivan) = try moved()
        let settings = Fixture.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let crew = [ivan] + outcome.crewChanges
        let person = CrewSheetPerson.matching(ivan, in: crew)

        let sheet = CrewMemberSheetBuilder(settings: settings, calendar: calendar).makeTable(
            person: person,
            sites: [here, there],
            results: [calculator.compute(outcome.source), calculator.compute(outcome.target)],
            range: date.yearMonth.range(in: calendar)
        )

        XCTAssertEqual(sheet.rows.count, 2)
        XCTAssertEqual(sheet.totals.first?.minutes, 480)
        XCTAssertEqual(sheet.eyebrow, "Timesheet · Hauptstraße 12 · Trg Pravde")
    }
}
