import XCTest
@testable import Hours

/// A site sheet that lists the whole month, as the personal timesheet does
/// (2026-11): every day a row, weekends quiet, public holidays named, paused
/// days and no-work days said, days nobody wrote left empty, and a holiday
/// the crew worked still marked.
final class SiteSheetMonthTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
    private let site = Site(name: "Trg Pravde", address: "Trg Pravde 1\n10000 Zagreb")
    private let other = Site(name: "Jarunski Dvori")
    private lazy var ana = CrewMember(siteID: site.id, name: "Ana", sortOrder: 0)
    private lazy var ivo = CrewMember(siteID: site.id, name: "Ivo", sortOrder: 1)
    private lazy var anaThere = CrewMember(siteID: other.id, name: "Ana", sortOrder: 0)

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
        present: [UUID],
        absences: [CrewAbsence] = [],
        note: String = ""
    ) -> SiteDay {
        SiteDay(
            siteID: (site ?? self.site).id, date: d(day), start: Fixture.time(7), end: Fixture.time(16),
            breakMinutes: 30, present: present.map { Attendance(memberID: $0) }, note: note, absences: absences
        )
    }

    private func sheet(
        _ days: [SiteDay],
        month: SiteSheetMonth? = nil,
        settings: AppSettings? = nil,
        placeholder: String = "—"
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder).makeTable(
            site: site, crew: [ana, ivo], results: days.map(calculator.compute), range: august,
            month: month ?? SiteSheetMonth(holidays: holidays)
        )
    }

    private func combined(
        _ days: [SiteDay],
        month: SiteSheetMonth? = nil,
        settings: AppSettings? = nil
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—").makeTable(
            sites: [site, other], crew: [ana, ivo, anaThere], results: days.map(calculator.compute), range: august,
            month: month ?? SiteSheetMonth(holidays: holidays)
        )
    }

    private func row(_ table: ReportTable, _ day: Int) -> ReportRow {
        table.rows.first { $0.id == d(day).key } ?? ReportRow(
            id: -99, values: [], minutes: [], isWorkingDay: true, balanceMinutes: 0, hasEntry: false
        )
    }

    private var everyone: [UUID] { [CrewMember.youID, ana.id, ivo.id] }
    private var holidayTint: TypeTint? {
        ReportDayHighlight.tint(for: DayTypeCatalog.standard.definition(for: .holiday))
    }

    // MARK: - Every day

    func testEveryDayOfTheMonthHasARowInOrder() {
        let t = sheet([worked(3, present: everyone), worked(4, present: everyone)])
        let days = t.rows.filter { $0.role == .day }
        XCTAssertEqual(days.map(\.id), august.days(in: calendar).map(\.key))
        XCTAssertEqual(days.count, 31)
        // The closing rows still close the sheet.
        XCTAssertEqual(t.rows.count, 31 + t.trailingSummaryRows)
        XCTAssertEqual(t.rows[31].role, .total)
        XCTAssertEqual(row(t, 1).values[0], "2026-08-01")
        XCTAssertEqual(row(t, 1).values[1], "Sat")
        XCTAssertEqual(t.columns.count, row(t, 1).values.count)
        XCTAssertEqual(t.columns.count, row(t, 1).minutes.count)
    }

    /// The days written are exactly the rows the sheet always had.
    func testTheWrittenDaysAreUnchanged() {
        let days = [
            worked(3, present: everyone, note: "Crane delivery"),
            worked(4, present: [CrewMember.youID, ivo.id], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])
        ]
        let full = sheet(days)
        let before = sheet(days, month: .writtenDaysOnly)
        XCTAssertEqual(before.rows.filter { $0.role == .day }.count, 2)
        for date in [3, 4] {
            XCTAssertEqual(row(full, date), row(before, date))
        }
        XCTAssertEqual(full.rows.filter { $0.role == .total }, before.rows.filter { $0.role == .total })
        XCTAssertEqual(full.writtenDayCount, 2)
        XCTAssertEqual(before.writtenDayCount, 2)
    }

    /// Nothing passed is the sheet as it was: only the days written.
    func testWithoutAMonthOnlyTheWrittenDaysAreListed() {
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = [worked(3, present: everyone)].map(calculator.compute)
        let builder = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
        let plain = builder.makeTable(site: site, crew: [ana, ivo], results: results, range: august)
        XCTAssertEqual(plain.rows.filter { $0.role == .day }.count, 1)
        XCTAssertEqual(
            plain,
            builder.makeTable(site: site, crew: [ana, ivo], results: results, range: august, month: .writtenDaysOnly)
        )
    }

    /// "Days on site" and the detail line count days written, not rows.
    func testTheFiguresStillCountTheDaysWritten() {
        let t = sheet([worked(3, present: everyone), worked(4, present: everyone)])
        XCTAssertEqual(t.tiles.first { $0.label == "Days on site" }?.value, "2")
        XCTAssertTrue(t.detail.contains("2 days on site"), t.detail)
        // Month total: two days of eight and a half hours each.
        XCTAssertEqual(t.rows[31].minutes[3], 1020)
        XCTAssertEqual(t.rows[32].values[3], "2")
    }

    // MARK: - A day nobody wrote

    func testAWorkDayNotWrittenIsLeftEmpty() {
        let t = sheet([worked(3, present: everyone)])
        let empty = row(t, 6)
        XCTAssertEqual(empty.values, ["2026-08-06", "Thu", "—", "", "—", "", "—", "", ""])
        XCTAssertTrue(empty.minutes.allSatisfy { $0 == nil })
        XCTAssertTrue(empty.isWorkingDay)
        XCTAssertFalse(empty.hasEntry)
        XCTAssertFalse(empty.isAbsence)
        XCTAssertNil(empty.dayTint, "not written is not red on a printed sheet, nor any colour")
        XCTAssertTrue(empty.groupTints.isEmpty)
        XCTAssertTrue(empty.flagged.isEmpty)
        // One dash across each person's pair.
        XCTAssertEqual(empty.mergedGroups, [2, 3, 4])
    }

    func testAFileLeavesTheEmptyCellsEmpty() {
        let t = sheet([worked(3, present: everyone)], placeholder: "")
        XCTAssertEqual(row(t, 6).values, ["2026-08-06", "Thu", "", "", "", "", "", "", ""])
    }

    func testAWeekendIsQuiet() {
        let t = sheet([worked(3, present: everyone)])
        for day in [1, 2, 8, 9] {
            let weekend = row(t, day)
            XCTAssertFalse(weekend.isWorkingDay, "\(day)")
            XCTAssertNil(weekend.dayTint, "\(day)")
            XCTAssertEqual(weekend.values.last, "")
            XCTAssertFalse(weekend.hasEntry)
        }
        XCTAssertTrue(row(t, 7).isWorkingDay)
    }

    /// The site's own work days decide what a weekend is.
    func testASiteWorkedOnSaturdaysHasNoQuietSaturday() {
        let saturdays = settings(setups: [site.id: SiteSetup(workDays: [3, 4, 5, 6, 7])])
        let t = sheet([worked(4, present: everyone)], settings: saturdays)
        XCTAssertTrue(row(t, 8).isWorkingDay, "Saturday is a work day here")
        XCTAssertFalse(row(t, 9).isWorkingDay)
        XCTAssertFalse(row(t, 10).isWorkingDay, "Monday is not")
        // A weekend day written is a day written, never quiet.
        let worked = sheet([worked(9, present: everyone)], settings: saturdays)
        XCTAssertTrue(row(worked, 9).isWorkingDay)
        XCTAssertTrue(row(worked, 9).hasEntry)
    }

    // MARK: - Public holidays

    func testAPublicHolidayIsNamedAndShaded() {
        let t = sheet([worked(3, present: everyone)])
        let holiday = row(t, 5)
        XCTAssertEqual(holiday.values.last, "Victory Day")
        XCTAssertEqual(holiday.dayTint, holidayTint)
        XCTAssertNotNil(holiday.dayTint)
        XCTAssertTrue(holiday.isAbsence)
        XCTAssertFalse(holiday.hasEntry)
        XCTAssertEqual(holiday.mergedGroups, [2, 3, 4])
        // On a weekend it is still the holiday.
        XCTAssertEqual(row(t, 15).values.last, "Assumption of Mary")
        XCTAssertEqual(row(t, 15).dayTint, holidayTint)
        // The legend says what the shading is.
        XCTAssertTrue(t.legend.hasSuffix(ExportLanguage.english(.dayHighlightLegend)), t.legend)
    }

    /// A holiday the crew worked keeps its mark: its name leads the note
    /// and the date and the day are shaded, the hours as on any day.
    func testAHolidayTheCrewWorkedKeepsItsMark() throws {
        let t = sheet([worked(5, present: [CrewMember.youID, ana.id], note: "Urgent pour")])
        let holiday = row(t, 5)
        XCTAssertEqual(holiday.values.last, "Victory Day · Urgent pour")
        XCTAssertEqual(holiday.values[2], "07:00–16:00")
        XCTAssertEqual(holiday.minutes[3], 510)
        XCTAssertTrue(holiday.hasEntry)
        XCTAssertNil(holiday.dayTint, "a day worked is not washed as a day off")
        let tint = try XCTUnwrap(holidayTint)
        XCTAssertEqual(holiday.groupTints, [0: tint, 1: tint])
        XCTAssertTrue(t.hasDayHighlights)
        // Without a note, the name alone.
        XCTAssertEqual(row(sheet([worked(5, present: everyone)]), 5).values.last, "Victory Day")
    }

    /// Only the days written, and the holiday worked is still marked.
    func testTheMarkIsThereWithOnlyWrittenDaysToo() {
        let t = sheet([worked(5, present: everyone)], month: SiteSheetMonth(holidays: holidays, listsEveryDay: false))
        XCTAssertEqual(t.rows.filter { $0.role == .day }.count, 1)
        XCTAssertEqual(t.rows[0].values.last, "Victory Day")
        XCTAssertEqual(t.rows[0].groupTints.keys.sorted(), [0, 1])
    }

    func testEachPersonsHolidaysOffAreCountedUnderTheTotals() throws {
        // Ana worked Victory Day; nobody worked the Assumption.
        let t = sheet([worked(3, present: everyone), worked(5, present: [ana.id])])
        let closing = try XCTUnwrap(t.rows.first { $0.values.first == "Public holidays" })
        XCTAssertEqual(closing.role, .count)
        // You, Ana, Ivo: hours columns 3, 5 and 7.
        XCTAssertEqual(closing.values[3], "2")
        XCTAssertEqual(closing.values[5], "1")
        XCTAssertEqual(closing.values[7], "2")
        XCTAssertEqual(t.trailingSummaryRows, 3)
        // No holidays in the month, no row.
        let none = sheet([worked(3, present: everyone)], month: SiteSheetMonth())
        XCTAssertNil(none.rows.first { $0.values.first == "Public holidays" })
        XCTAssertEqual(none.trailingSummaryRows, 2)
    }

    /// A holiday outside the range is none of this sheet's.
    func testAHolidayOutsideTheRangeIsNotCounted() {
        let t = sheet(
            [worked(3, present: everyone)],
            month: SiteSheetMonth(holidays: [Fixture.date(2026, 9, 1): "Elsewhere"])
        )
        XCTAssertNil(t.rows.first { $0.values.first == "Public holidays" })
        XCTAssertEqual(t.rows.filter { $0.role == .day }.count, 31)
    }

    // MARK: - Paused, and no work

    func testAPausedWorkDaySaysPaused() {
        let paused = settings(setups: [site.id: SiteSetup(pause: SitePause(start: d(17), end: d(23)))])
        let t = sheet([worked(3, present: everyone), worked(19, present: everyone)], settings: paused)
        for day in [17, 18, 20, 21] {
            XCTAssertEqual(row(t, day).values.last, "Paused", "\(day)")
            XCTAssertEqual(row(t, day).dayTint, .gray)
            XCTAssertTrue(row(t, day).isWorkingDay)
        }
        // A day written during the pause is a day written.
        XCTAssertEqual(row(t, 19).values[2], "07:00–16:00")
        XCTAssertNil(row(t, 19).dayTint)
        // The weekend in it is a weekend, and the days around it are plain.
        XCTAssertEqual(row(t, 22).values.last, "")
        XCTAssertFalse(row(t, 22).isWorkingDay)
        XCTAssertNil(row(t, 22).dayTint)
        XCTAssertEqual(row(t, 14).values.last, "")
        XCTAssertEqual(row(t, 24).values.last, "")
        XCTAssertNil(row(t, 24).dayTint)
    }

    /// A holiday during a pause is the holiday.
    func testAHolidayComesBeforeAPause() {
        let paused = settings(setups: [site.id: SiteSetup(pause: SitePause(start: d(3)))])
        let t = sheet([], settings: paused)
        XCTAssertEqual(row(t, 5).values.last, "Victory Day")
        XCTAssertEqual(row(t, 5).dayTint, holidayTint)
        XCTAssertEqual(row(t, 6).values.last, "Paused")
    }

    func testANoWorkDayKeepsItsReasonAmongTheOtherDays() {
        let noWork = SiteDay.noWork(.dayOff, siteID: site.id, date: d(6), jobID: nil)
        let rained = SiteDay.noWork(.badWeather, siteID: site.id, date: d(7), jobID: nil)
        let t = sheet([worked(3, present: everyone), noWork, rained])
        XCTAssertEqual(row(t, 6).values.last, "No work · Day off")
        XCTAssertEqual(row(t, 6).dayTint, DayTypeCatalog.standard.definition(for: .dayOff).tint)
        XCTAssertTrue(row(t, 6).hasEntry)
        XCTAssertEqual(row(t, 7).values.last, "No work · Bad weather")
        XCTAssertEqual(row(t, 7).dayTint, DayTypeCatalog.standard.definition(for: .badWeather).tint)
        XCTAssertEqual(t.rows.filter { $0.role == .day }.count, 31)
    }

    // MARK: - People

    func testSomeoneAwayShowsWhyInTheirOwnCell() {
        let t = sheet([
            worked(3, present: everyone),
            worked(4, present: [CrewMember.youID], absences: [
                CrewAbsence(memberID: ana.id, dayTypeID: .sick),
                CrewAbsence(memberID: ivo.id, dayTypeID: .vacation)
            ])
        ])
        let day = row(t, 4)
        XCTAssertEqual(day.values[4], "Sick leave")
        XCTAssertEqual(day.values[6], "Vacation")
        XCTAssertEqual(day.groupTints[3], DayTypeCatalog.standard.definition(for: .sick).tint)
        XCTAssertEqual(day.groupTints[4], DayTypeCatalog.standard.definition(for: .vacation).tint)
        XCTAssertNil(day.dayTint)
        XCTAssertEqual(t.rows.first { $0.values.first == "Sick days" }?.values[5], "1")
        XCTAssertEqual(t.rows.first { $0.values.first == "Leave days" }?.values[7], "1")
        // The same words a timesheet's Type column has.
        XCTAssertEqual(day.values[4], DayTypeCatalog.standard.definition(for: .sick).exportName(in: .english))
    }

    // MARK: - Several sites

    func testACombinedSheetListsEveryDayOnce() {
        let t = combined([
            worked(3, present: everyone),
            worked(4, on: other, present: [CrewMember.youID, anaThere.id])
        ])
        let days = t.rows.filter { $0.role == .day }
        XCTAssertEqual(days.map(\.id), august.days(in: calendar).map(\.key))
        XCTAssertEqual(t.columns.prefix(3), [.date, .weekday, .site])
        let empty = row(t, 6)
        XCTAssertEqual(empty.values, ["2026-08-06", "Thu", "", "—", "", "—", "", "—", "", ""])
        XCTAssertEqual(empty.mergedGroups, [3, 4, 5])
        XCTAssertFalse(empty.hasEntry)
        XCTAssertNil(empty.splitDay)
        XCTAssertEqual(row(t, 5).values.last, "Victory Day")
        XCTAssertEqual(row(t, 5).dayTint, holidayTint)
        XCTAssertFalse(row(t, 8).isWorkingDay)
        XCTAssertEqual(t.writtenDayCount, 2)
        XCTAssertEqual(t.tiles.first { $0.label == "Days on site" }?.value, "2")
    }

    /// A day is quiet only when none of the sites works it, and paused only
    /// when every site that does is paused.
    func testOnACombinedSheetTheSitesDecideTogether() {
        let setups = [
            site.id: SiteSetup(workDays: [2, 3, 4, 5, 6], pause: SitePause(start: d(10), end: d(14))),
            other.id: SiteSetup(workDays: [2, 3, 4, 5, 6, 7], pause: SitePause(start: d(12), end: d(15)))
        ]
        let t = combined([worked(3, present: everyone)], settings: settings(setups: setups))
        XCTAssertTrue(row(t, 8).isWorkingDay, "Saturday is a work day on one of them")
        XCTAssertFalse(row(t, 9).isWorkingDay)
        XCTAssertEqual(row(t, 10).values.last, "", "only one of the two is paused")
        XCTAssertNil(row(t, 10).dayTint)
        XCTAssertEqual(row(t, 12).values.last, "Paused")
        XCTAssertEqual(row(t, 12).dayTint, .gray)
        // Saturday 15th: a holiday first.
        XCTAssertEqual(row(t, 15).values.last, "Assumption of Mary")
    }

    func testOnACombinedSheetAWorkedHolidayIsMarkedOnItsFirstRow() throws {
        let t = combined([
            worked(5, present: [CrewMember.youID], note: "Pour"),
            worked(5, on: other, present: [anaThere.id])
        ])
        // The first site's row carries the date; the second site's follows it.
        let key = d(5).key
        let rows = t.rows.filter { $0.id == key || $0.id == -(key * 10 + 1) }
        XCTAssertEqual(rows.count, 2)
        let tint = try XCTUnwrap(holidayTint)
        XCTAssertEqual(rows[0].values.last, "Victory Day · Pour")
        XCTAssertEqual(rows[0].groupTints[0], tint)
        XCTAssertEqual(rows[0].groupTints[1], tint)
        XCTAssertEqual(rows[1].values.last, "")
        XCTAssertNil(rows[1].groupTints[0])
        // Each person's holidays off: you worked one of the two.
        let closing = try XCTUnwrap(t.rows.first { $0.values.first == "Public holidays" })
        XCTAssertEqual(closing.values[4], "1")
    }

    func testWithOnlyWrittenDaysACombinedSheetIsAsItWas() {
        let days = [worked(3, present: everyone), worked(4, on: other, present: [CrewMember.youID, anaThere.id])]
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let before = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—").makeTable(
            sites: [site, other], crew: [ana, ivo, anaThere], results: days.map(calculator.compute), range: august
        )
        XCTAssertEqual(combined(days, month: .writtenDaysOnly), before)
        XCTAssertEqual(before.rows.filter { $0.role == .day }.count, 2)
    }

    // MARK: - On the page and in the files

    /// A big crew's parts each list the whole month, marks and all.
    func testEveryPartOfASplitSheetListsEveryDay() throws {
        let t = sheet([worked(3, present: everyone), worked(5, present: everyone)])
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 2)
        XCTAssertEqual(parts.count, 2)
        let tint = try XCTUnwrap(holidayTint)
        for part in parts {
            XCTAssertEqual(part.rows.filter { $0.role == .day }.count, 31)
            XCTAssertEqual(row(part, 5).groupTints[0], tint)
            XCTAssertEqual(row(part, 15).dayTint, tint)
            XCTAssertEqual(row(part, 15).values.last, "Assumption of Mary")
            XCTAssertFalse(row(part, 8).isWorkingDay)
            XCTAssertNotNil(part.rows.first { $0.values.first == "Public holidays" })
        }
        XCTAssertEqual(row(parts[1], 6).mergedGroups, [2])
    }

    func testTheWorkbookAndTheCSVHoldEveryDay() {
        let t = sheet([worked(3, present: everyone)], placeholder: "")
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        for day in august.days(in: calendar) {
            XCTAssertTrue(csv.contains(ExportDateStyle.iso.string(for: day)), "\(day.key)")
        }
        XCTAssertTrue(csv.contains("Victory Day"))
        let workbook = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertFalse(workbook.isEmpty)
    }

    func testEveryExportLanguageHasTheWords() {
        let paused = SiteSetup(pause: SitePause(start: d(17), end: d(21)))
        var seenPaused = Set<String>()
        for language in ExportLanguage.allCases where language != .device {
            let t = sheet([worked(3, present: everyone)], settings: settings(language: language, setups: [site.id: paused]))
            XCTAssertEqual(t.rows.filter { $0.role == .day }.count, 31, language.rawValue)
            XCTAssertEqual(row(t, 17).values.last, language(.sitePaused), language.rawValue)
            XCTAssertFalse(language(.sitePaused).isEmpty)
            XCTAssertEqual(
                t.rows.first { $0.role == .count && $0.values.first == language(.publicHolidays) }?.values[3], "2",
                language.rawValue
            )
            // A holiday's name is the user's own and is not translated.
            XCTAssertEqual(row(t, 5).values.last, "Victory Day")
            seenPaused.insert(language(.sitePaused))
        }
        XCTAssertGreaterThan(seenPaused.count, 5)
    }

    // MARK: - What kind of day

    func testTheKindOfADayNobodyWrote() {
        let weekdays = SiteSetup(workDays: [2, 3, 4, 5, 6])
        let kind = { (day: Int, setups: [SiteSetup]) in
            SiteSheetEmptyDay.of(self.d(day), setups: setups, holidays: self.holidays, calendar: self.calendar)
        }
        XCTAssertEqual(kind(5, [weekdays]), .holiday("Victory Day"))
        XCTAssertEqual(kind(8, [weekdays]), .notAWorkDay)
        XCTAssertEqual(kind(6, [weekdays]), .notWritten)
        // No work days set: Monday to Friday.
        XCTAssertEqual(kind(8, [SiteSetup()]), .notAWorkDay)
        XCTAssertEqual(kind(6, [SiteSetup()]), .notWritten)
        XCTAssertEqual(kind(6, []), .notWritten)
        XCTAssertEqual(kind(6, [SiteSetup(pause: SitePause(start: d(6)))]), .paused)
        XCTAssertEqual(kind(8, [SiteSetup(pause: SitePause(start: d(6)))]), .notAWorkDay)
        XCTAssertEqual(kind(6, [SiteSetup(pause: SitePause(start: d(6))), weekdays]), .notWritten)
    }
}
