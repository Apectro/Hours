import XCTest
@testable import Hours

/// One person's own sheet: their days on every site, for a month, to check
/// against a payslip or to sign. It is the crew's sheet for one person: the
/// same kind of table, closed by the same rows (the month model is in
/// `CrewMemberSheetMonthTests`).
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
        signatures: Bool = true,
        placeholder: String = "—"
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
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

    /// A closing row by its label, and its figure under the hours.
    private func closing(_ table: ReportTable, _ label: String) -> String? {
        guard let row = table.rows.first(where: { $0.role != .day && $0.values.first == label }) else { return nil }
        return value(table, row, .worked)
    }

    private func closingLabels(_ table: ReportTable) -> [String] {
        table.rows.filter { $0.role != .day }.compactMap(\.values.first)
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

        XCTAssertEqual(t.kind, .siteSheet, "the crew's sheet, for one person")
        XCTAssertTrue(t.isOnePersonSheet)
        XCTAssertEqual(t.ownerName, "Ana Horvat")
        XCTAssertEqual(t.headline, "Ana Horvat")
        XCTAssertEqual(t.columns, [.date, .weekday, .site, .times, .breakTime, .worked, .note])
        XCTAssertEqual(t.columnHeadings(), ["Date", "Day", "Site", "From–to", "Break", "Hours", "Notes"])

        let rows = dayRows(t)
        XCTAssertEqual(rows.map(\.id), [20260803, 20260805])
        XCTAssertEqual(rows[0].values, ["2026-08-03", "Mon", "Bau Süd", "07:00–16:00", "30m", "8h 30m", "Crane"])
        XCTAssertEqual(rows[1].values, ["2026-08-05", "Wed", "Halle 3", "07:00–12:00", "30m", "4h 30m", ""])
        XCTAssertEqual(rows[0].minutes[5], 510, "hours are a figure the workbook can add")
        XCTAssertEqual(rows[0].minutes[4], 30)
        XCTAssertNil(rows[0].minutes[3])

        // The crew sheet's eyebrow; the sites, in their order, in the title.
        XCTAssertEqual(t.eyebrow, "Site hours · August 2026")
        XCTAssertEqual(t.sitesText, "Bau Süd · Halle 3")
        XCTAssertEqual(t.title, "Bau Süd · Halle 3 — August 2026")
        XCTAssertTrue(t.byline.contains("August 2026"), t.byline)
        XCTAssertTrue(t.byline.contains("Recorded by Marijo"), t.byline)
    }

    /// The same columns whatever the month holds, as the crew's sheet always
    /// has its notes: only the site comes and goes.
    func testOneSiteHasNoSiteColumn() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [Attendance(memberID: ana.id, breakMinutes: 0)])
        ])
        XCTAssertEqual(t.columns, [.date, .weekday, .times, .breakTime, .worked, .note])
        XCTAssertEqual(t.columnHeadings(), ["Date", "Day", "From–to", "Break", "Hours", "Notes"])
        XCTAssertEqual(t.sitesText, "Bau Süd")
        XCTAssertEqual(dayRows(t)[1].values[3], "—", "no break is a dash, not 0m")
        XCTAssertNil(dayRows(t)[1].minutes[3])
        // Every column ruled off from the next, and none headed twice.
        XCTAssertEqual(t.validGroups.map(\.span), [1, 1, 1, 1, 1, 1])
        XCTAssertFalse(t.hasSpanningGroups)
        XCTAssertNil(SiteSheetBuilder.peopleCount(in: t), "never split by people")
    }

    /// A day away says why in the notes — no Reason column — in the words
    /// and on the wash the crew's sheet gives the person's cell.
    func testASickDayIsARowWithItsReasonAndCounted() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            day(south, 5, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)]),
            day(south, 6, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(hall.id))]),
            day(south, 7, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(nil))])
        ])
        XCTAssertEqual(t.columns, [.date, .weekday, .times, .breakTime, .worked, .note])
        let rows = dayRows(t)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(value(t, rows[0], .note), "")
        XCTAssertEqual(value(t, rows[1], .note), "Sick leave")
        XCTAssertEqual(value(t, rows[1], .worked), "—")
        XCTAssertNil(rows[1].minutes[4])
        XCTAssertTrue(rows[1].isAbsence)
        XCTAssertTrue(rows[1].hasEntry, "a day away was written for them")
        let catalog = DayTypeCatalog.standard
        XCTAssertEqual(rows[1].dayTint, ReportDayHighlight.tint(for: catalog.definition(for: .sick)))
        XCTAssertEqual(value(t, rows[2], .note), "Vacation")
        XCTAssertEqual(rows[2].dayTint, ReportDayHighlight.tint(for: catalog.definition(for: .vacation)))
        XCTAssertEqual(value(t, rows[3], .note), "Other site · Halle 3")
        XCTAssertFalse(rows[3].isAbsence, "on another site is not absence")
        XCTAssertNil(rows[3].dayTint)
        XCTAssertEqual(value(t, rows[4], .note), "Other site")

        // On the page the reason is said once, from the times to the notes.
        XCTAssertEqual(t.dayBanner(of: rows[1]), ReportDayBanner(text: "Sick leave", columns: 2..<6))
        XCTAssertEqual(t.dayBanner(of: rows[3])?.text, "Other site · Halle 3")
        XCTAssertNil(t.dayBanner(of: rows[0]), "a day worked has its hours")

        // The crew sheet's closing rows, the figures under the hours.
        XCTAssertEqual(closingLabels(t), ["Month total", "Days worked", "Sick days", "Leave days"])
        XCTAssertEqual(closing(t, "Month total"), "8h 30m")
        XCTAssertEqual(closing(t, "Days worked"), "1")
        XCTAssertEqual(closing(t, "Sick days"), "1")
        XCTAssertEqual(closing(t, "Leave days"), "1")
        XCTAssertEqual(t.trailingSummaryRows, 4)
        XCTAssertTrue(t.totals.isEmpty, "no summary block: the closing rows say it, as on the crew's sheet")
        XCTAssertEqual(t.tiles.map(\.label), ["Worked", "Days on site", "Sick days", "Leave days"])
        XCTAssertEqual(t.tiles.map(\.value), ["8h 30m", "1", "1", "1"])
        XCTAssertEqual(t.writtenDayCount, 5)
    }

    /// The crew sheet's header: the kind and the month in the eyebrow, the
    /// person as the title, their site and its address in grey, and the
    /// hours and days on site as the two figures.
    func testThePrintedHeaderIsThePersonThenTheKindAndTheMonth() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)])
        ])
        let header = t.pageHeader(madeOn: Fixture.date(2026, 11, 3), calendar: calendar)
        XCTAssertEqual(header.title, "Ana")
        XCTAssertEqual(header.kindLine, "Site hours · August 2026")
        XCTAssertTrue(header.detailLine.hasPrefix("Bau Süd · "), header.detailLine)
        XCTAssertEqual(header.figures.map(\.label), ["Worked", "Days on site"])
        XCTAssertEqual(header.figures.map(\.value), ["8h 30m", "1"])
    }

    func testTheHeaderNamesTheSiteBeforeItsAddress() {
        let yard = Site(name: "Yard", address: "Ilica 1\n10000 Zagreb")
        let ana = CrewMember(siteID: yard.id, name: "Ana")
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let t = CrewMemberSheetBuilder(settings: settings, calendar: calendar).makeTable(
            person: .matching(ana, in: [ana]),
            sites: [yard],
            results: [calculator.compute(day(yard, 3, present: [Attendance(memberID: ana.id)]))],
            range: august
        )
        let header = t.pageHeader(madeOn: Fixture.date(2026, 11, 3), calendar: calendar)
        XCTAssertTrue(header.detailLine.hasPrefix("Yard · Ilica 1, 10000 Zagreb · "), header.detailLine)
    }

    func testNoSickOrLeaveRowsWhenThereWereNone() throws {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [Attendance(memberID: ana.id)])
        ])
        XCTAssertEqual(closingLabels(t), ["Month total", "Days worked"])
        XCTAssertEqual(t.tiles.map(\.value), ["17h", "2"])
        // The month total is ruled off under the days, under the hours and
        // the break, as figures a workbook can add.
        let total = try XCTUnwrap(t.rows.first { $0.role == .total })
        XCTAssertEqual(total.values, ["Month total", "", "", "1h", "17h", ""])
        XCTAssertEqual(total.minutes[4], 1020)
        XCTAssertEqual(total.minutes[3], 60)
        XCTAssertEqual(t.rows.last?.role, .count)
        XCTAssertEqual(t.rows.last?.values, ["Days worked", "", "", "", "2", ""])
        XCTAssertNil(t.totalRow, "the total is one of the rows, as on the crew's sheet")
        XCTAssertEqual(t.trailingSummaryRows, 2)
        XCTAssertEqual(Set(t.rows.map(\.id)).count, t.rows.count)
    }

    func testAMonthWithoutABreakHasNoBreakTotal() throws {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id, breakMinutes: 0)])
        ])
        let total = try XCTUnwrap(t.rows.first { $0.role == .total })
        XCTAssertEqual(total.values[3], "")
        XCTAssertNil(total.minutes[3])
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
        XCTAssertFalse(t.columns.contains(.site), "the reason row was the only trace of the other site")
        XCTAssertEqual(rows[0].values.last, "")
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
        XCTAssertEqual(t.tiles.first(where: { $0.label == "Days on site" })?.value, "1")
        XCTAssertEqual(closing(t, "Days worked"), "1")
        XCTAssertEqual(closing(t, "Month total"), "8h")
        XCTAssertEqual(t.writtenDayCount, 1, "a day on two sites is one day")
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
        XCTAssertEqual(t.tiles.first(where: { $0.label == "Days on site" })?.value, "1")
        XCTAssertEqual(closing(t, "Days worked"), "0", "a day with no hours is not a day worked, as on the crew's sheet")
        XCTAssertNil(t.dayBanner(of: row), "their 0h stays under the hours")
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

    /// Nothing written for them: no day rows without a month to list, and
    /// nothing to share either way.
    func testAnEmptyMonthHasNoDaysAndNothingWritten() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [])
        XCTAssertTrue(dayRows(t).isEmpty)
        XCTAssertEqual(t.writtenDayCount, 0)
        XCTAssertEqual(closingLabels(t), ["Month total", "Days worked"])
        XCTAssertEqual(closing(t, "Month total"), "0h")
        XCTAssertEqual(t.title, "Hours — August 2026")
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
            ["Datum", "Tag", "Baustelle", "Von–bis", "Pause", "Stunden", "Notizen"]
        )
        let rows = dayRows(t)
        XCTAssertEqual(rows[0].values[1], "Mo")
        XCTAssertEqual(value(t, rows[2], .note), "Krankheit")
        XCTAssertEqual(value(t, rows[3], .note), "Urlaub")
        XCTAssertEqual(t.eyebrow, "Baustellenstunden · August 2026")
        XCTAssertEqual(t.title, "Bau Süd · Halle 3 — August 2026")
        XCTAssertEqual(closingLabels(t), ["Monatssumme", "Arbeitstage", "Krankheitstage", "Urlaubstage"])
        XCTAssertEqual(t.tiles.map(\.label), ["Gearbeitet", "Tage auf der Baustelle", "Krankheitstage", "Urlaubstage"])
        XCTAssertTrue(t.byline.contains("Erfasst von Marijo"), t.byline)
        XCTAssertEqual(
            t.legend,
            "Stunden nach Abzug der Pause. "
                + "Farbig hinterlegt = krank, Urlaub, Feiertag oder keine Arbeit, in der Farbe der Tagesart."
        )
    }

    func testCroatian() {
        let ana = CrewMember(siteID: south.id, name: "Ana")
        let t = table(for: .matching(ana, in: [ana]), days: [
            day(south, 3, present: [Attendance(memberID: ana.id)]),
            day(south, 4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            day(south, 5, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(nil))])
        ], settings: settings(language: .croatian))
        XCTAssertEqual(t.columnHeadings(), ["Datum", "Dan", "Od–do", "Pauza", "Sati", "Bilješke"])
        let rows = dayRows(t)
        XCTAssertEqual(value(t, rows[1], .note), "Bolovanje")
        XCTAssertEqual(value(t, rows[2], .note), ExportLanguage.croatian(.otherSite))
        XCTAssertEqual(t.eyebrow, "Sati na gradilištu · kolovoz 2026.")
        XCTAssertEqual(closingLabels(t).prefix(2), ["Ukupno za mjesec", "Radni dani"])
        XCTAssertEqual(t.tiles.map(\.label).prefix(2), ["Odrađeno", "Dani na gradilištu"])
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
        let t = table(
            for: .matching(ana, in: [ana]),
            days: [
                day(south, 3, present: [Attendance(memberID: ana.id)]),
                day(south, 4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])
            ],
            placeholder: ""
        )
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        // One heading row, the days, then the closing rows in the table.
        XCTAssertTrue(csv.hasPrefix("Date,Day,From–to,Break,Hours,Notes\r\n"), csv)
        XCTAssertTrue(csv.contains("2026-08-04,Tue,,,,Sick leave\r\n"), csv)
        XCTAssertTrue(csv.contains("Month total,,,30m,8h 30m,\r\n"), csv)
        XCTAssertTrue(csv.contains("Sick days,,,,1,\r\n"), csv)
        XCTAssertTrue(csv.contains("Name,Ana Horvat"), csv)

        // The workbook keeps the person's name on its own line under the
        // title, heads each column once, and totals the hours as a sum.
        // Readable straight out of the archive: its entries are stored
        // uncompressed.
        let data = XLSXWriter.data(for: t, preferences: ExportPreferences())
        let sheet = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(sheet.contains("Bau Süd — August 2026"), "the title")
        XCTAssertFalse(sheet.contains("Bau Süd — August 2026 — "), "the eyebrow is not run into the title")
        XCTAssertTrue(sheet.contains("Ana Horvat"))
        XCTAssertTrue(sheet.contains("Month total"))
        XCTAssertTrue(sheet.contains("SUM("), "the month total is a formula over the days")
        XCTAssertFalse(data.isEmpty)
    }
}

private extension SiteDay {
    func with(month: Int) -> SiteDay {
        var day = self
        day.date = CalendarDate(year: date.year, month: month, day: date.day)
        return day
    }
}
