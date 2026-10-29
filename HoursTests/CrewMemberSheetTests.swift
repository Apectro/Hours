import XCTest
@testable import Hours

/// One person's own sheet: their days on every site, for a month, to check
/// against a payslip or to sign.
final class CrewMemberSheetTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private let south = Site(name: "Bau Süd", sortOrder: 0)
    private let hall = Site(name: "Halle 3", sortOrder: 1)

    private func settings(owner: String = "Marijo", language: ExportLanguage = .english) -> AppSettings {
        Fixture.settings(export: ExportPreferences(language: language, ownerName: owner))
    }

    private func day(
        _ site: Site,
        _ d: Int,
        present: [Attendance],
        absences: [CrewAbsence] = [],
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(16),
        note: String = "",
        badWeather: Bool = false
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, d),
            start: start,
            end: end,
            breakMinutes: 30,
            present: present,
            note: note,
            isBadWeatherStop: badWeather,
            absences: absences
        )
    }

    private func table(
        for person: CrewSheetPerson,
        days: [SiteDay],
        settings: AppSettings? = nil,
        range: CalendarDateRange? = nil,
        signatures: Bool = true
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(
                person: person,
                sites: [hall, south],
                results: days.map(calculator.compute),
                range: range ?? august,
                includesSignatures: signatures
            )
    }

    private func dayRows(_ table: ReportTable) -> [ReportRow] {
        table.rows.filter { $0.role == .day }
    }

    private func value(_ table: ReportTable, _ row: ReportRow, _ column: ReportColumn) -> String? {
        guard let index = table.columns.firstIndex(of: column), index < row.values.count else { return nil }
        return row.values[index]
    }

    // MARK: - Who

    func testAPersonIsTheSameNameOnEverySite() {
        let anaSouth = CrewMember(siteID: south.id, name: "Ana Horvat")
        let anaHall = CrewMember(siteID: hall.id, name: "  ana  horvat ")
        let ivo = CrewMember(siteID: hall.id, name: "Ivo")
        let person = CrewSheetPerson.matching(anaSouth, in: [anaSouth, anaHall, ivo])
        XCTAssertEqual(person.name, "Ana Horvat")
        XCTAssertEqual(person.memberIDs, [anaSouth.id, anaHall.id])
        XCTAssertEqual(CrewSheetPerson.you(name: "Marijo").memberIDs, [CrewMember.youID])
    }

    func testThePeopleOnASitesSheetAreYouThenTheCrewInOrder() {
        let ana = CrewMember(siteID: south.id, name: "Ana", sortOrder: 1)
        let ivo = CrewMember(siteID: south.id, name: "Ivo", sortOrder: 0)
        let nobody = CrewMember(siteID: south.id, name: "Nobody", sortOrder: 2)
        let anaHall = CrewMember(siteID: hall.id, name: "Ana")
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = [
            day(south, 3, present: [Attendance(memberID: ana.id), Attendance(memberID: CrewMember.youID)]),
            day(south, 4, present: [], absences: [CrewAbsence(memberID: ivo.id, dayTypeID: .sick)]),
            day(hall, 5, present: [Attendance(memberID: anaHall.id)])
        ].map(calculator.compute)
        let people = CrewMemberSheetBuilder.people(
            on: south.id,
            crew: [ana, ivo, nobody, anaHall],
            results: results,
            range: august,
            ownerName: "Marijo"
        )
        XCTAssertEqual(people.map(\.name), ["Marijo", "Ivo", "Ana"])
        XCTAssertEqual(people[2].memberIDs, [ana.id, anaHall.id], "Ana's sheet covers her other site too")
    }

    // MARK: - Rows

    func testOneRowPerDayOnEverySiteTheyWorked() {
        let ana = CrewMember(siteID: south.id, name: "Ana Horvat")
        let anaHall = CrewMember(siteID: hall.id, name: "Ana Horvat")
        let other = CrewMember(siteID: south.id, name: "Ivo")
        let person = CrewSheetPerson.matching(ana, in: [ana, anaHall, other])
        let t = table(for: person, days: [
            day(hall, 5, present: [Attendance(memberID: anaHall.id, end: Fixture.time(12))]),
            day(south, 3, present: [Attendance(memberID: ana.id), Attendance(memberID: other.id)], note: "Crane"),
            // Not hers: Ivo alone.
            day(south, 4, present: [Attendance(memberID: other.id)]),
            // Outside the month.
            day(south, 3, present: [Attendance(memberID: ana.id)]).with(month: 9)
        ])

        XCTAssertEqual(t.kind, .timesheet)
        XCTAssertEqual(t.ownerName, "Ana Horvat")
        XCTAssertEqual(t.headline, "Ana Horvat")
        XCTAssertEqual(t.columns, [.date, .weekday, .location, .times, .breakTime, .worked, .note])
        XCTAssertEqual(t.columnHeadings(), ["Date", "Day", "Site", "From–to", "Break", "Hours", "Notes"])

        let rows = dayRows(t)
        XCTAssertEqual(rows.map(\.id), [20260803, 20260805])
        XCTAssertEqual(rows[0].values, ["2026-08-03", "Mon", "Bau Süd", "07:00–16:00", "30m", "8h 30m", "Crane"])
        XCTAssertEqual(rows[1].values, ["2026-08-05", "Wed", "Halle 3", "07:00–12:00", "30m", "4h 30m", "—"])
        XCTAssertEqual(rows[0].minutes[5], 510, "hours are a figure the workbook can add")
        XCTAssertEqual(rows[0].minutes[4], 30)
        XCTAssertNil(rows[0].minutes[3])

        // The sites, in their order, in the title block.
        XCTAssertEqual(t.eyebrow, "Timesheet · Bau Süd · Halle 3")
        XCTAssertEqual(t.title, "Bau Süd · Halle 3 — August 2026")
        XCTAssertTrue(t.byline.contains("August 2026"), t.byline)
        XCTAssertTrue(t.byline.contains("Recorded by Marijo"), t.byline)
    }

    func testOneSiteHasNoSiteColumnAndNoEmptyNoteColumn() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [Attendance(memberID: ana.id, breakMinutes: 0)])
        ])
        XCTAssertEqual(t.columns, [.date, .weekday, .times, .breakTime, .worked])
        XCTAssertEqual(t.eyebrow, "Timesheet · Bau Süd")
        XCTAssertEqual(dayRows(t)[1].values[3], "—", "no break is a dash, not 0m")
        XCTAssertNil(dayRows(t)[1].minutes[3])
    }

    func testASickDayIsARowWithItsReasonAndCounted() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            day(south, 5, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)]),
            day(south, 6, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(hall.id))]),
            day(south, 7, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(nil))])
        ])
        XCTAssertEqual(t.columns, [.date, .weekday, .times, .breakTime, .worked, .dayType])
        XCTAssertEqual(t.columnHeadings().last, "Reason")
        let rows = dayRows(t)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(value(t, rows[0], .dayType), "—")
        XCTAssertEqual(value(t, rows[1], .dayType), "Sick leave")
        XCTAssertEqual(value(t, rows[1], .worked), "—")
        XCTAssertNil(rows[1].minutes[4])
        XCTAssertTrue(rows[1].isAbsence, "a sick day is washed as the timesheet washes absence")
        XCTAssertEqual(value(t, rows[2], .dayType), "Vacation")
        XCTAssertEqual(value(t, rows[3], .dayType), "Halle 3")
        XCTAssertFalse(rows[3].isAbsence, "on another site is not absence")
        XCTAssertEqual(value(t, rows[4], .dayType), "Other site")

        XCTAssertEqual(t.totals.map(\.label), ["Total worked", "Days on site", "Sick days", "Leave days"])
        XCTAssertEqual(t.totals.map(\.value), ["8h 30m", "1", "1", "1"])
        XCTAssertEqual(t.tiles.map(\.label), ["Worked", "Days on site", "Sick days", "Leave days"])
    }

    func testNoSickOrLeaveLinesWhenThereWereNone() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [Attendance(memberID: ana.id)])
        ])
        XCTAssertEqual(t.totals.map(\.label), ["Total worked", "Days on site"])
        XCTAssertEqual(t.totals.map(\.value), ["17h", "2"])
        XCTAssertEqual(t.totals.first?.minutes, 1020)
        XCTAssertEqual(t.totals.last?.count, 2)
        XCTAssertEqual(t.tiles.map(\.value), ["17h", "2"])
        // The ruled total under the days, under the hours and the break.
        let total = try? XCTUnwrap(t.totalRow)
        XCTAssertEqual(total?.values.first, "Total")
        XCTAssertEqual(total?.minutes[4], 1020)
        XCTAssertEqual(total?.minutes[3], 60)
        XCTAssertEqual(t.trailingSummaryRows, 0)
    }

    func testADayNotOnTheCrewYetHasNoRow() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let ivo = CrewMember(siteID: south.id, name: "Ivo")
        let t = table(for: .matching(ana, in: [ana, ivo]), days: [
            // Ana not ticked and no reason: she was not on this crew yet.
            day(south, 3, present: [Attendance(memberID: ivo.id)]),
            day(south, 4, present: [Attendance(memberID: ana.id), Attendance(memberID: ivo.id)])
        ])
        XCTAssertEqual(dayRows(t).map(\.id), [20260804])
    }

    func testAReasonOnADayWorkedElsewhereGivesNoSecondRow() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let anaHall = CrewMember(siteID: hall.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana, anaHall]), days: [
            day(south, 3, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(hall.id))]),
            day(hall, 3, present: [Attendance(memberID: anaHall.id)])
        ])
        let rows = dayRows(t)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].values[2], "07:00–16:00")
        XCTAssertFalse(t.columns.contains(.location), "the reason row was the only trace of the other site")
        XCTAssertFalse(t.columns.contains(.dayType))
    }

    func testTwoSitesOnOneDayAreTwoRowsAndOneDayOnSite() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let anaHall = CrewMember(siteID: hall.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana, anaHall]), days: [
            day(hall, 3, present: [Attendance(memberID: anaHall.id)], start: Fixture.time(13), end: Fixture.time(17)),
            day(south, 3, present: [Attendance(memberID: ana.id)], start: Fixture.time(7), end: Fixture.time(12))
        ])
        let rows = dayRows(t)
        XCTAssertEqual(rows.map { $0.values[2] }, ["Bau Süd", "Halle 3"])
        XCTAssertEqual(t.totals.first(where: { $0.label == "Days on site" })?.value, "1")
        XCTAssertEqual(t.totals.first?.value, "8h")
        XCTAssertEqual(Set(rows.map(\.id)).count, 2, "row ids stay unique")
    }

    // MARK: - Weekends and holidays, as the site sheet has them

    func testAWeekendWorkedIsAnOrdinaryRowAndAHolidayNobodyWorkedIsNone() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            // Saturday 8 August.
            day(south, 8, present: [Attendance(memberID: ana.id)])
        ])
        let rows = dayRows(t)
        // Saturday 15 August, Assumption, has no site day and so no row.
        XCTAssertEqual(rows.map(\.id), [20260808])
        XCTAssertEqual(rows[0].values[1], "Sat")
        XCTAssertTrue(rows[0].isWorkingDay, "the site sheet draws a worked weekend like any day")
        XCTAssertFalse(rows[0].isAbsence)
    }

    func testABadWeatherStopLeadsTheNote() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)], start: nil, end: nil, badWeather: true)
        ])
        let row = dayRows(t)[0]
        XCTAssertEqual(value(t, row, .note), "Bad weather")
        XCTAssertEqual(value(t, row, .times), "—")
        XCTAssertEqual(value(t, row, .worked), "0h")
        XCTAssertEqual(t.totals.first(where: { $0.label == "Days on site" })?.value, "1")
    }

    // MARK: - You, and signatures

    func testYourOwnSheetUsesYourName() {
        let t = table(for: .you(name: ""), days: [day(south, 3, present: [Attendance(memberID: CrewMember.youID)])])
        XCTAssertEqual(t.ownerName, "Marijo")
        XCTAssertFalse(t.byline.contains("Recorded by"), "you do not record your own hours for yourself")
        let nameless = table(
            for: .you(name: ""),
            days: [day(south, 3, present: [Attendance(memberID: CrewMember.youID)])],
            settings: settings(owner: "")
        )
        XCTAssertEqual(nameless.ownerName, "You")
    }

    func testTheLinesToSignOnFollowTheSignaturesSwitch() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let days = [day(south, 3, present: [Attendance(memberID: ana.id)])]
        XCTAssertEqual(
            table(for: .matching(ana, in: [ana]), days: days).signatures,
            ["Employee · date, signature", "Checked · date, signature"]
        )
        XCTAssertEqual(table(for: .matching(ana, in: [ana]), days: days, signatures: false).signatures, [])
    }

    func testAnEmptyMonthIsAnEmptySheet() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [])
        XCTAssertTrue(t.isEmpty)
    }

    func testARangeThatIsNotAMonthIsTitledByItsDates() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 12, present: [Attendance(memberID: ana.id)])
        ], range: range)
        XCTAssertEqual(dayRows(t).count, 1)
        XCTAssertEqual(t.title, "Bau Süd — 2026-08-03 – 2026-08-09")
    }

    // MARK: - German and Croatian

    func testGerman() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let anaHall = CrewMember(siteID: hall.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana, anaHall]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)], note: "Kran"),
            day(hall, 4, present: [Attendance(memberID: anaHall.id)]),
            day(south, 5, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            day(south, 6, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)])
        ], settings: settings(language: .german))
        XCTAssertEqual(
            t.columnHeadings(),
            ["Datum", "Tag", "Baustelle", "Von–bis", "Pause", "Stunden", "Grund", "Notizen"]
        )
        let rows = dayRows(t)
        XCTAssertEqual(rows[0].values[1], "Mo")
        XCTAssertEqual(value(t, rows[2], .dayType), "Krankheit")
        XCTAssertEqual(value(t, rows[3], .dayType), "Urlaub")
        XCTAssertEqual(t.eyebrow, "Stundenzettel · Bau Süd · Halle 3")
        XCTAssertEqual(t.title, "Bau Süd · Halle 3 — August 2026")
        XCTAssertEqual(
            t.totals.map(\.label),
            ["Gesamt gearbeitet", "Tage auf der Baustelle", "Krankheitstage", "Urlaubstage"]
        )
        XCTAssertTrue(t.byline.contains("Erfasst von Marijo"), t.byline)
        XCTAssertEqual(t.totalRow?.values.first, "Summe")
    }

    func testCroatian() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            day(south, 5, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(nil))])
        ], settings: settings(language: .croatian))
        XCTAssertEqual(t.columnHeadings(), ["Datum", "Dan", "Od–do", "Pauza", "Sati", "Razlog"])
        let rows = dayRows(t)
        XCTAssertEqual(value(t, rows[1], .dayType), "Bolovanje")
        XCTAssertEqual(value(t, rows[2], .dayType), ExportLanguage.croatian(.otherSite))
        XCTAssertEqual(t.eyebrow, "Evidencija radnog vremena · Bau Süd")
        XCTAssertEqual(t.totals.map(\.label).prefix(2), ["Ukupno odrađeno", "Dani na gradilištu"])
        XCTAssertEqual(t.signatures, ["Zaposlenik · datum, potpis", "Provjereno · datum, potpis"])
    }

    // MARK: - Files

    func testTheFileIsNamedForThePersonAndTheMonth() {
        let naming = ExportNaming(settings: settings(language: .german), calendar: calendar)
        XCTAssertEqual(naming.crewSheetFileName("Ana Horvat", range: august), "Ana Horvat – August 2026")
        let week = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))
        XCTAssertEqual(naming.crewSheetFileName("Ana", range: week), "Ana – 2026-08-03 to 2026-08-09")
        let croatian = ExportNaming(settings: settings(language: .croatian), calendar: calendar)
        XCTAssertTrue(croatian.crewSheetFileName("Ana", range: august).hasPrefix("Ana – "))
        XCTAssertFalse(croatian.crewSheetFileName("Ana", range: august).contains("August"))
    }

    func testTheSheetWritesAsCSVAndAWorkbook() {
        let ana = CrewMember(siteID: south.id, name: "Ana Horvat")
        let t = table(for: .matching(ana, in: [ana]), days: [day(south, 3, present: [Attendance(memberID: ana.id)])])
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        XCTAssertTrue(csv.hasPrefix("Date,Day,From–to,Break,Hours\r\n"), csv)
        XCTAssertTrue(csv.contains("Name,Ana Horvat"), csv)
        let workbook = XLSXWriter.data(for: t, preferences: ExportPreferences())
        XCTAssertFalse(workbook.isEmpty)
    }
}

private extension SiteDay {
    func with(month: Int) -> SiteDay {
        var day = self
        day.date = CalendarDate(year: date.year, month: month, day: date.day)
        return day
    }
}
