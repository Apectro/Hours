import XCTest
@testable import Hours

/// One person's own sheet lists the month as the crew's sheet does
/// (2026-11): every day a row, weekends quiet, public holidays named, a
/// pause and a no-work day said, days with nothing of theirs left empty,
/// their days away on the day type's wash in the crew sheet's words, a
/// holiday they worked still marked, and the crew sheet's closing rows.
final class CrewMemberSheetMonthTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
    private let site = Site(name: "Trg Pravde", sortOrder: 0, address: "Trg Pravde 1\n10000 Zagreb")
    private let other = Site(name: "Jarunski Dvori", sortOrder: 1)
    private lazy var ana = CrewMember(siteID: site.id, name: "Ana", sortOrder: 0)
    private lazy var ivo = CrewMember(siteID: site.id, name: "Ivo", sortOrder: 1)
    private lazy var anaThere = CrewMember(siteID: other.id, name: "Ana", sortOrder: 0)
    private lazy var person = CrewSheetPerson.matching(ana, in: [ana, ivo, anaThere])

    /// Wednesday 5 August and Saturday 15 August.
    private let victoryDay = Fixture.date(2026, 8, 5)
    private let assumption = Fixture.date(2026, 8, 15)
    private var holidays: [CalendarDate: String] {
        [victoryDay: "Victory Day", assumption: "Assumption of Mary"]
    }

    private func d(_ day: Int) -> CalendarDate { Fixture.date(2026, 8, day) }

    private func settings(
        language: ExportLanguage = .english,
        setups: [UUID: SiteSetup] = [:]
    ) -> AppSettings {
        var settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        for (id, setup) in setups { settings.setSiteSetup(setup, for: id) }
        return settings
    }

    private func worked(
        _ day: Int,
        on site: Site? = nil,
        present: [Attendance],
        absences: [CrewAbsence] = [],
        note: String = "",
        allowance: [UUID] = [],
        kilometres: Int = 0
    ) -> SiteDay {
        SiteDay(
            siteID: (site ?? self.site).id, date: d(day), start: Fixture.time(7), end: Fixture.time(16),
            breakMinutes: 30, present: present, note: note, absences: absences,
            allowanceMemberIDs: allowance, kilometres: kilometres
        )
    }

    private func here(_ day: Int, note: String = "") -> SiteDay {
        worked(day, present: [Attendance(memberID: ana.id), Attendance(memberID: ivo.id)], note: note)
    }

    private func sheet(
        _ days: [SiteDay],
        month: SiteSheetMonth? = nil,
        settings: AppSettings? = nil,
        placeholder: String = "—"
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder).makeTable(
            person: person, sites: [site, other], results: days.map(calculator.compute), range: august,
            month: month ?? SiteSheetMonth(holidays: holidays)
        )
    }

    /// The crew's own sheet of the same days, to hold the person's to.
    private func crewSheet(_ days: [SiteDay], settings: AppSettings? = nil) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—").makeTable(
            site: site, crew: [ana, ivo], results: days.map(calculator.compute), range: august,
            month: SiteSheetMonth(holidays: holidays)
        )
    }

    private func dayRows(_ table: ReportTable) -> [ReportRow] {
        table.rows.filter { $0.role == .day }
    }

    private func row(_ table: ReportTable, _ day: Int) -> ReportRow {
        table.rows.first { $0.id == d(day).key } ?? ReportRow(
            id: -99, values: [], minutes: [], isWorkingDay: true, balanceMinutes: 0, hasEntry: false
        )
    }

    private func closing(_ table: ReportTable, _ label: String) -> String? {
        guard let index = table.columns.firstIndex(of: .worked),
              let row = table.rows.first(where: { $0.role != .day && $0.values.first == label }) else { return nil }
        return row.values[index]
    }

    private func closingLabels(_ table: ReportTable) -> [String] {
        table.rows.filter { $0.role != .day }.compactMap(\.values.first)
    }

    private func tint(_ id: DayTypeID) -> TypeTint? {
        ReportDayHighlight.tint(for: DayTypeCatalog.standard.definition(for: id))
    }

    // MARK: - Every day

    func testEveryDayOfTheMonthHasARowInOrder() {
        let t = sheet([here(3), here(4)])
        let days = dayRows(t)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.map(\.id), (1...31).map { d($0).key })
        XCTAssertEqual(days.first?.values.prefix(2), ["2026-08-01", "Sat"])
        XCTAssertEqual(t.rows.count, 31 + t.trailingSummaryRows)
        XCTAssertEqual(Set(t.rows.map(\.id)).count, t.rows.count, "row ids stay unique")
        // Every row has a value for every column.
        XCTAssertTrue(t.rows.allSatisfy { $0.values.count == t.columns.count && $0.minutes.count == t.columns.count })
    }

    func testTheWrittenDaysReadAsOnTheCrewsSheet() {
        let t = sheet([here(3, note: "Crane")])
        XCTAssertEqual(row(t, 3).values, ["2026-08-03", "Mon", "07:00–16:00", "30m", "8h 30m", "Crane"])
        XCTAssertTrue(row(t, 3).hasEntry)
        XCTAssertTrue(row(t, 3).isWorkingDay)
        XCTAssertNil(row(t, 3).dayTint)
        // The same times and hours the crew's sheet prints in their columns.
        let crew = crewSheet([here(3, note: "Crane")])
        XCTAssertEqual(Array(row(crew, 3).values[2...3]), ["07:00–16:00", "8h 30m"])
        XCTAssertEqual(row(crew, 3).values.last, "Crane")
    }

    func testWithoutAMonthOnlyTheirWrittenDaysAreListed() {
        let days = [here(3), here(4), worked(6, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])]
        let calculator = SiteDayCalculator(settings: settings(), calendar: calendar)
        let plain = CrewMemberSheetBuilder(settings: settings(), calendar: calendar).makeTable(
            person: person, sites: [site, other], results: days.map(calculator.compute), range: august
        )
        XCTAssertEqual(dayRows(plain).map(\.id), [d(3).key, d(4).key, d(6).key])
        let off = sheet(days, month: SiteSheetMonth(holidays: holidays, listsEveryDay: false))
        XCTAssertEqual(dayRows(off).map(\.id), [d(3).key, d(4).key, d(6).key])
    }

    func testTheFiguresCountTheDaysWrittenForThem() {
        let t = sheet([here(3), here(4), worked(6, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])])
        XCTAssertEqual(t.writtenDayCount, 3, "two days worked and a day away")
        XCTAssertEqual(t.tiles.first { $0.label == "Days on site" }?.value, "2")
        XCTAssertEqual(closing(t, "Days worked"), "2")
        XCTAssertEqual(closing(t, "Month total"), "17h")
        // A month with nothing of theirs has nothing to share.
        XCTAssertEqual(sheet([]).writtenDayCount, 0)
        XCTAssertEqual(dayRows(sheet([])).count, 31, "and still lists the month")
    }

    // MARK: - Days with nothing of theirs

    func testAWorkDayNotWrittenIsLeftEmpty() {
        let t = sheet([here(3)])
        let empty = row(t, 4)
        XCTAssertEqual(empty.values, ["2026-08-04", "Tue", "—", "—", "—", ""])
        XCTAssertFalse(empty.hasEntry)
        XCTAssertTrue(empty.isWorkingDay)
        XCTAssertFalse(empty.isAbsence)
        XCTAssertNil(empty.dayTint, "nothing is shaded: a printed sheet accuses nobody")
        XCTAssertNil(t.dayBanner(of: empty))
    }

    func testAFileLeavesTheEmptyCellsEmpty() {
        let t = sheet([here(3)], placeholder: "")
        XCTAssertEqual(row(t, 4).values, ["2026-08-04", "Tue", "", "", "", ""])
        XCTAssertEqual(row(t, 5).values, ["2026-08-05", "Wed", "", "", "", "Victory Day"])
    }

    func testAWeekendIsQuiet() {
        let t = sheet([here(3)])
        let saturday = row(t, 8)
        XCTAssertEqual(saturday.values, ["2026-08-08", "Sat", "—", "—", "—", ""])
        XCTAssertFalse(saturday.isWorkingDay, "muted, as a timesheet's weekend")
        XCTAssertFalse(saturday.isAbsence)
        XCTAssertNil(saturday.dayTint)
        XCTAssertFalse(row(t, 9).isWorkingDay)
        XCTAssertTrue(row(t, 10).isWorkingDay)
    }

    func testASiteWorkedOnSaturdaysHasNoQuietSaturday() {
        let setup = SiteSetup(workDays: SiteSetup.mondayToFriday.union([7]))
        let t = sheet([here(3)], settings: settings(setups: [site.id: setup]))
        XCTAssertTrue(row(t, 8).isWorkingDay)
        XCTAssertFalse(row(t, 9).isWorkingDay)
    }

    func testAWeekendTheyWorkedIsAnOrdinaryRow() {
        let t = sheet([here(8)])
        XCTAssertTrue(row(t, 8).isWorkingDay)
        XCTAssertTrue(row(t, 8).hasEntry)
        XCTAssertEqual(row(t, 8).values[4], "8h 30m")
    }

    func testAPublicHolidayIsNamedAndShaded() {
        let t = sheet([here(3)])
        let holiday = row(t, 5)
        XCTAssertEqual(holiday.values, ["2026-08-05", "Wed", "—", "—", "—", "Victory Day"])
        XCTAssertEqual(holiday.dayTint, tint(.holiday))
        XCTAssertTrue(holiday.isAbsence)
        XCTAssertFalse(holiday.hasEntry)
        // A holiday first, on a weekend too.
        XCTAssertEqual(row(t, 15).values.last, "Assumption of Mary")
        XCTAssertEqual(row(t, 15).dayTint, tint(.holiday))
        // Said once from the times to the notes on the page.
        XCTAssertEqual(t.dayBanner(of: holiday), ReportDayBanner(text: "Victory Day", columns: 2..<6))
        XCTAssertTrue(t.legend.contains("Shaded"))
    }

    func testAPausedWorkDaySaysPaused() {
        let setup = SiteSetup(pause: SitePause(start: d(24), end: d(28)))
        let t = sheet([here(3)], settings: settings(setups: [site.id: setup]))
        XCTAssertEqual(row(t, 24).values.last, "Paused")
        XCTAssertEqual(row(t, 24).dayTint, .gray)
        XCTAssertFalse(row(t, 24).isAbsence)
        XCTAssertEqual(row(t, 28).values.last, "Paused")
        XCTAssertEqual(row(t, 31).values.last, "", "after the pause")
        XCTAssertEqual(row(t, 22).values.last, "", "a weekend is a weekend, paused or not")
        XCTAssertEqual(t.dayBanner(of: row(t, 24))?.text, "Paused")
    }

    func testANoWorkDayOfTheirSiteSaysWhy() {
        let noWork = SiteDay.noWork(.dayOff, siteID: site.id, date: d(6), jobID: nil)
        let t = sheet([here(3), noWork])
        let day = row(t, 6)
        XCTAssertEqual(day.values, ["2026-08-06", "Thu", "—", "—", "—", "No work · Day off"])
        XCTAssertEqual(day.dayTint, DayTypeCatalog.standard.definition(for: .dayOff).tint)
        XCTAssertFalse(day.hasEntry, "the site's day, not one written for them")
        XCTAssertEqual(t.dayBanner(of: day)?.text, "No work · Day off")
        // The crew's sheet says the same of the day.
        XCTAssertEqual(row(crewSheet([here(3), noWork]), 6).values.last, "No work · Day off")
        XCTAssertEqual(row(crewSheet([here(3), noWork]), 6).dayTint, day.dayTint)
    }

    func testANoWorkDayOfASiteTheyAreNotOnSaysNothing() {
        // Ana has no day on the other site this month.
        let elsewhere = SiteDay.noWork(.dayOff, siteID: other.id, date: d(6), jobID: nil)
        let t = sheet([here(3), elsewhere])
        XCTAssertEqual(row(t, 6).values.last, "")
        XCTAssertNil(row(t, 6).dayTint)
    }

    /// The crew worked and they were not ticked, with no reason given: not
    /// on the crew that day, which is not away.
    func testADayTheCrewWorkedWithoutThemIsEmptyNotAbsent() {
        let withoutHer = worked(4, present: [Attendance(memberID: ivo.id)], note: "Formwork")
        let t = sheet([here(3), withoutHer])
        let day = row(t, 4)
        XCTAssertEqual(day.values, ["2026-08-04", "Tue", "—", "—", "—", ""], "not even the crew's note")
        XCTAssertFalse(day.hasEntry)
        XCTAssertFalse(day.isAbsence)
        XCTAssertNil(day.dayTint)
        XCTAssertEqual(closingLabels(t), ["Month total", "Days worked", "Public holidays"])
        XCTAssertEqual(t.writtenDayCount, 1)
    }

    // MARK: - Days away

    func testADayAwayHasTheCrewSheetsWashAndWording() {
        let days = [
            here(3),
            worked(4, present: [Attendance(memberID: ivo.id)], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            worked(6, present: [Attendance(memberID: ivo.id)], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)])
        ]
        let t = sheet(days)
        let crew = crewSheet(days)
        // On the crew's sheet Ana is the first person: columns 2 and 3, group 2.
        XCTAssertEqual(row(t, 4).values.last, row(crew, 4).values[2])
        XCTAssertEqual(row(t, 4).values.last, "Sick leave")
        XCTAssertEqual(row(t, 4).dayTint, row(crew, 4).groupTints[2])
        XCTAssertEqual(row(t, 6).values.last, row(crew, 6).values[2])
        XCTAssertEqual(row(t, 6).dayTint, row(crew, 6).groupTints[2])
        XCTAssertTrue(row(t, 4).isAbsence)
        XCTAssertTrue(row(t, 4).hasEntry)
        XCTAssertEqual(row(t, 4).values.dropLast().suffix(3), ["—", "—", "—"])
        XCTAssertEqual(closing(t, "Sick days"), "1")
        XCTAssertEqual(closing(t, "Leave days"), "1")
        XCTAssertEqual(closing(t, "Sick days"), crew.rows.first { $0.values.first == "Sick days" }?.values[3])
    }

    func testADayOffAndTimeInLieuAreNeitherSickNorLeave() {
        let t = sheet([
            here(3),
            worked(4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .dayOff)]),
            worked(6, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .timeOffInLieu)])
        ])
        XCTAssertEqual(row(t, 4).values.last, DayTypeCatalog.standard.definition(for: .dayOff).exportName(in: .english))
        XCTAssertNil(closing(t, "Sick days"))
        XCTAssertNil(closing(t, "Leave days"))
    }

    // MARK: - Holidays worked

    func testAHolidayTheyWorkedKeepsItsMark() throws {
        let t = sheet([here(3), here(5, note: "Urgent pour")])
        let day = row(t, 5)
        XCTAssertTrue(day.hasEntry)
        XCTAssertEqual(day.values, ["2026-08-05", "Wed", "07:00–16:00", "30m", "8h 30m", "Victory Day · Urgent pour"])
        XCTAssertNil(day.dayTint, "the row is a day worked")
        let holiday = try XCTUnwrap(tint(.holiday))
        XCTAssertEqual(day.groupTints, [0: holiday, 1: holiday], "the date and the day are shaded")
        XCTAssertNil(t.dayBanner(of: day))
        XCTAssertEqual(row(sheet([here(5)]), 5).values.last, "Victory Day")
    }

    func testTheMarkIsThereWithOnlyWrittenDaysToo() {
        let t = sheet([here(5)], month: SiteSheetMonth(holidays: holidays, listsEveryDay: false))
        XCTAssertEqual(dayRows(t).count, 1)
        XCTAssertEqual(row(t, 5).values.last, "Victory Day")
        XCTAssertFalse(row(t, 5).groupTints.isEmpty)
    }

    func testAHolidayTheyWereSickOnNamesBoth() {
        let t = sheet([here(3), worked(5, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])])
        XCTAssertEqual(row(t, 5).values.last, "Victory Day · Sick leave")
        XCTAssertEqual(row(t, 5).dayTint, tint(.sick))
        XCTAssertTrue(row(t, 5).groupTints.isEmpty)
    }

    func testTheirHolidaysOffAreCountedUnderTheTotals() {
        // Two public holidays in the month; she worked one.
        XCTAssertEqual(closing(sheet([here(3)]), "Public holidays"), "2")
        XCTAssertEqual(closing(sheet([here(3), here(5)]), "Public holidays"), "1")
        XCTAssertNil(closing(sheet([here(5), here(15)]), "Public holidays"), "no row when she worked them all")
        // None in the month, none counted.
        XCTAssertNil(closing(sheet([here(3)], month: SiteSheetMonth()), "Public holidays"))
        // A holiday outside the range is not counted.
        let september = SiteSheetMonth(holidays: [Fixture.date(2026, 9, 1): "Later"])
        XCTAssertNil(closing(sheet([here(3)], month: september), "Public holidays"))
    }

    // MARK: - The closing rows, the legend, the lines to sign on

    func testTheClosingRowsAreTheCrewSheets() {
        var allowance = settings()
        allowance.allowance = AllowancePreferences(isEnabled: true, dailyAllowanceCents: 25_00, centsPerKilometre: 30)
        let days = [
            worked(3, present: [Attendance(memberID: ana.id), Attendance(memberID: ivo.id)],
                   allowance: [ana.id, ivo.id], kilometres: 42),
            worked(4, present: [Attendance(memberID: ana.id)], allowance: [], kilometres: 10),
            worked(6, present: [Attendance(memberID: ivo.id)], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            worked(7, present: [Attendance(memberID: ivo.id)], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)])
        ]
        let t = sheet(days, settings: allowance)
        XCTAssertEqual(
            closingLabels(t),
            ["Month total", "Days worked", "Sick days", "Leave days", "Public holidays", "Allowance days"]
        )
        XCTAssertEqual(closing(t, "Allowance days"), "1")
        XCTAssertEqual(t.trailingSummaryRows, 6)
        let roles: [ReportRowRole] = t.rows.suffix(6).map { $0.role }
        XCTAssertEqual(roles, [.total, .count, .count, .count, .count, .count])
        // The crew's sheet of the same days has the same rows in the same
        // order, and the vehicle's kilometres, which belong to no person.
        let crew = crewSheet(days, settings: allowance)
        let crewLabels: [String] = crew.rows.filter { $0.role != .day }.compactMap { $0.values.first }
        XCTAssertEqual(crewLabels, closingLabels(t) + ["Kilometres"])
        // Every figure is under the hours, the label in the date column
        // with the day beside it empty, so the page runs the label on.
        for row in t.rows.suffix(5) {
            XCTAssertEqual(row.values[1], "")
            XCTAssertEqual(row.values.enumerated().filter { !$0.element.isEmpty }.map(\.offset), [0, 4])
        }
        // With the allowance switched off there is no such row.
        XCTAssertFalse(closingLabels(sheet(days)).contains("Allowance days"))
    }

    func testTheLegendNamesOnlyWhatTheSheetHas() {
        // Hours after the break, nothing orange, nothing shaded.
        let plain = sheet([here(3)], month: SiteSheetMonth())
        XCTAssertEqual(plain.legend, "Hours are after the break.")
        // Left early: orange, on the times and the hours.
        let early = sheet(
            [worked(3, present: [Attendance(memberID: ana.id, end: Fixture.time(14, 30))])],
            month: SiteSheetMonth()
        )
        XCTAssertEqual(row(early, 3).flagged, [2, 4])
        XCTAssertEqual(early.legend, "Hours are after the break. Orange = came late or left early.")
        // A shaded day adds what the shading means.
        let shaded = sheet([here(3)])
        XCTAssertEqual(
            shaded.legend,
            "Hours are after the break. Shaded = sick, on leave, a holiday or no work, in the day type's colour."
        )
        // Nothing worked: nothing to say about hours.
        XCTAssertEqual(sheet([], month: SiteSheetMonth()).legend, "")
    }

    func testTheLegendFollowsPaidBreaks() {
        let paidJob = UUID(uuidString: "00000000-0000-4000-8000-0000000000DD")!
        var settings = settings()
        settings.jobs = [
            Job(id: Job.primaryID, name: "Main", breaksArePaid: false, sortOrder: 0),
            Job(id: paidJob, name: "Builder", breaksArePaid: true, sortOrder: 1)
        ]
        var paid = here(3)
        paid.jobID = paidJob
        XCTAssertEqual(
            sheet([paid], month: SiteSheetMonth(), settings: settings).legend,
            "Hours worked, paid break included."
        )
        // A month with both says neither.
        XCTAssertEqual(sheet([paid, here(4)], month: SiteSheetMonth(), settings: settings).legend, "")
    }

    func testTheLinesToSignOnAreKept() {
        XCTAssertEqual(sheet([here(3)]).signatures, ["Employee · date, signature", "Checked · date, signature"])
    }

    // MARK: - Several sites

    func testTwoSitesHaveASiteColumnAndDecideTheEmptyDaysTogether() {
        let setups: [UUID: SiteSetup] = [
            // The first site is paused for the last week; the other is not,
            // and works Saturdays.
            site.id: SiteSetup(pause: SitePause(start: d(24), end: d(28))),
            other.id: SiteSetup(workDays: SiteSetup.mondayToFriday.union([7]))
        ]
        let t = sheet(
            [here(3), worked(4, on: other, present: [Attendance(memberID: anaThere.id)])],
            settings: settings(setups: setups)
        )
        XCTAssertEqual(t.columns, [.date, .weekday, .site, .times, .breakTime, .worked, .note])
        XCTAssertEqual(dayRows(t).count, 31)
        XCTAssertEqual(row(t, 3).values[2], "Trg Pravde")
        XCTAssertEqual(row(t, 4).values[2], "Jarunski Dvori")
        XCTAssertEqual(row(t, 6).values, ["2026-08-06", "Thu", "", "—", "—", "—", ""])
        XCTAssertTrue(row(t, 8).isWorkingDay, "one of their sites works Saturdays")
        XCTAssertFalse(row(t, 9).isWorkingDay)
        XCTAssertEqual(row(t, 24).values.last, "", "paused only when every site that works the day is")
        XCTAssertEqual(t.dayBanner(of: row(t, 5)), ReportDayBanner(text: "Victory Day", columns: 3..<7))
        XCTAssertEqual(t.sitesText, "Trg Pravde · Jarunski Dvori")
        XCTAssertEqual(t.address, "", "no one address across two sites")
    }

    func testADayOnTwoSitesIsTwoRowsUnderOneDate() {
        let t = sheet([
            worked(3, present: [Attendance(memberID: ana.id, end: Fixture.time(12))]),
            worked(3, on: other, present: [Attendance(memberID: anaThere.id, start: Fixture.time(13))])
        ])
        let rows = dayRows(t).filter { $0.values[0] == "2026-08-03" }
        XCTAssertEqual(rows.map { $0.values[2] }, ["Trg Pravde", "Jarunski Dvori"])
        XCTAssertEqual(dayRows(t).count, 32)
        XCTAssertEqual(t.writtenDayCount, 1)
        XCTAssertEqual(closing(t, "Days worked"), "1")
    }

    func testOneSitesSheetCarriesItsAddress() {
        let t = sheet([here(3)])
        XCTAssertEqual(t.address, "Trg Pravde 1, 10000 Zagreb")
        let header = t.pageHeader(madeOn: Fixture.date(2026, 9, 1), calendar: calendar)
        XCTAssertEqual(header.title, "Ana")
        XCTAssertEqual(header.kindLine, "Site hours · August 2026")
        XCTAssertTrue(header.detailLine.hasPrefix("Trg Pravde · Trg Pravde 1, 10000 Zagreb · "), header.detailLine)
    }

    // MARK: - Files and languages

    func testTheWorkbookAndTheCSVHoldEveryDay() {
        let t = sheet([here(3)], placeholder: "")
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { $0.hasPrefix("2026-08-") }.count, 31)
        XCTAssertTrue(csv.contains("2026-08-05,Wed,,,,Victory Day"), csv)
        XCTAssertTrue(csv.contains("Public holidays,,,,2,"), csv)
        let workbook = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(workbook.contains("Assumption of Mary"))
        XCTAssertTrue(workbook.contains("Month total"))
    }

    func testEveryExportLanguageHasTheWords() {
        for language in ExportLanguage.allCases where language != .device {
            let setup = SiteSetup(pause: SitePause(start: d(24), end: d(28)))
            let t = sheet(
                [
                    worked(3, present: [Attendance(memberID: ana.id, end: Fixture.time(14, 30))]),
                    worked(4, present: [], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
                    worked(6, present: [], absences: [CrewAbsence(memberID: ana.id, reason: .otherSite(nil))])
                ],
                settings: settings(language: language, setups: [site.id: setup])
            )
            XCTAssertEqual(dayRows(t).count, 31, language.rawValue)
            XCTAssertEqual(row(t, 24).values.last, language(.sitePaused), language.rawValue)
            XCTAssertEqual(row(t, 6).values.last, language(.otherSite), language.rawValue)
            XCTAssertEqual(
                closingLabels(t),
                [language(.monthTotal), language(.daysWorked), language(.sickDays), language(.publicHolidays)],
                language.rawValue
            )
            XCTAssertEqual(
                t.legend,
                [language(.hoursAfterBreakLegend), language(.lateOrEarlyLegend), language(.dayHighlightLegend)]
                    .joined(separator: " "),
                language.rawValue
            )
            for term in [ExportTerm.hoursAfterBreakLegend, .hoursWithPaidBreakLegend, .lateOrEarlyLegend] {
                XCTAssertFalse(language(term).isEmpty, "\(language.rawValue) \(term.rawValue)")
                XCTAssertTrue(language(term).hasSuffix("."), "\(language.rawValue) \(term.rawValue)")
            }
            XCTAssertEqual(t.eyebrow, "\(language(.siteHours)) · \(t.period)", language.rawValue)
        }
    }
}
