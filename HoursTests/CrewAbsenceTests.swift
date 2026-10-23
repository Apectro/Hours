import XCTest
@testable import Hours

/// Why someone was not on site: sick, on leave, a day off. Per day, on the
/// site day; carried into your own calendar when it is you; printed on the
/// site sheet.
final class CrewAbsenceTests: XCTestCase {
    private let siteID = UUID()
    private let ivo = UUID()
    private let date = Fixture.workingTuesday
    private let calendar = Fixture.calendar()

    private func siteDay(present: [UUID] = [], absences: [CrewAbsence] = [], date: CalendarDate? = nil) -> SiteDay {
        SiteDay(
            siteID: siteID,
            date: date ?? self.date,
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present.map { Attendance(memberID: $0) },
            absences: absences
        )
    }

    // MARK: - The model

    func testAReasonIsGivenToSomeoneNotTicked() {
        let day = siteDay(present: [CrewMember.youID]).settingAbsence(.sick, for: ivo)
        XCTAssertEqual(day.absence(for: ivo), .sick)
        XCTAssertEqual(day.absences, [CrewAbsence(memberID: ivo, dayTypeID: .sick)])
        XCTAssertNil(day.absence(for: CrewMember.youID))
    }

    func testAReasonReplacesTheLastOneAndNoReasonClearsIt() {
        let sick = siteDay().settingAbsence(.sick, for: ivo)
        let vacation = sick.settingAbsence(.vacation, for: ivo)
        XCTAssertEqual(vacation.absences, [CrewAbsence(memberID: ivo, dayTypeID: .vacation)])
        XCTAssertEqual(vacation.settingAbsence(nil, for: ivo).absences, [])
    }

    /// Absent means not here: giving a reason to someone ticked unticks them.
    func testAReasonForSomeoneTickedUnticksThem() {
        let day = siteDay(present: [ivo]).settingAbsence(.sick, for: ivo)
        XCTAssertNil(day.attendance(for: ivo))
        XCTAssertEqual(day.absence(for: ivo), .sick)
    }

    func testTickingThePersonClearsTheReason() {
        let sick = siteDay().settingAbsence(.sick, for: ivo)
        let ticked = sick.togglingPresence(of: ivo)
        XCTAssertNotNil(ticked.attendance(for: ivo))
        XCTAssertNil(ticked.absence(for: ivo))
        XCTAssertEqual(ticked.absences, [])

        let unticked = ticked.togglingPresence(of: ivo)
        XCTAssertNil(unticked.attendance(for: ivo))
        XCTAssertNil(unticked.absence(for: ivo), "unticking gives no reason by itself")
    }

    /// Someone both present and absent can only come from sync merging two
    /// edits; present wins, since hours were written for them.
    func testPresentWinsOverAStrayReason() {
        let day = siteDay(present: [ivo], absences: [CrewAbsence(memberID: ivo, dayTypeID: .sick)])
        XCTAssertNil(day.absence(for: ivo))
    }

    /// "Ivo was sick" is worth keeping on a day nobody else came.
    func testADayWithOnlyAReasonIsNotBlank() {
        var day = SiteDay(siteID: siteID, date: date)
        XCTAssertTrue(day.isBlank)
        day = day.settingAbsence(.sick, for: ivo)
        XCTAssertFalse(day.isBlank)
    }

    func testAbsencesRoundTripAndDecodeLeniently() throws {
        let day = siteDay(present: [CrewMember.youID]).settingAbsence(.sick, for: ivo)
        XCTAssertEqual(try JSONDecoder().decode(SiteDay.self, from: JSONEncoder().encode(day)), day)

        // A day written before absences existed has none.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(day)) as? [String: Any])
        object.removeValue(forKey: "absences")
        let older = try JSONDecoder().decode(SiteDay.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(older.absences, [])
        XCTAssertEqual(older.present, day.present)

        // A damaged list is none, not a failed day.
        object["absences"] = "garbage"
        let damaged = try JSONDecoder().decode(SiteDay.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(damaged.absences, [])
        XCTAssertEqual(damaged.present, day.present)
    }

    /// The shape of a site day for the decoders in 1.0 and the 1.1 builds
    /// before absences: they must still read a day that has them.
    private struct OlderSiteDay: Decodable {
        var siteID: UUID
        var date: CalendarDate
        var present: [Attendance]
        var note: String
    }

    func testAnOlderDecoderStillReadsADayWithAbsences() throws {
        let day = siteDay(present: [CrewMember.youID]).settingAbsence(.sick, for: ivo)
        let older = try JSONDecoder().decode(OlderSiteDay.self, from: JSONEncoder().encode(day))
        XCTAssertEqual(older.present.map(\.memberID), [CrewMember.youID], "the absent person is not read as present")
    }

    func testAnOlderBackupStillRestoresWithTheAbsences() throws {
        let day = siteDay(present: [CrewMember.youID]).settingAbsence(.vacation, for: ivo)
        let archive = BackupArchive(settings: AppSettings(), days: [], holidays: [], siteDays: [day])
        let restored = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(restored.siteDays?.first?.absence(for: ivo), .vacation)
    }

    // MARK: - The reasons offered

    func testTheReasonsAreTheDayTypesThatMeanAbsent() {
        let custom = DayTypeDefinition(
            id: DayTypeID("training"), name: "Training", symbolName: "book", tint: .green,
            expectation: .creditedAbsence, showsTimesByDefault: false
        )
        let workLike = DayTypeDefinition(
            id: DayTypeID("night"), name: "Night shift", symbolName: "moon", tint: .indigo,
            expectation: .scheduled, showsTimesByDefault: true
        )
        let catalog = DayTypeCatalog(custom: [custom, workLike])
        XCTAssertEqual(
            catalog.absenceReasons.map(\.id),
            [.vacation, .sick, .personal, .timeOffInLieu, .dayOff, DayTypeID("training")]
        )
    }

    // MARK: - Your own calendar

    func testYouAbsentWithAReasonGivesYourDayThatType() {
        let merged = SiteCalendarSync.merged(
            personal: nil,
            siteDays: [siteDay(present: [ivo]).settingAbsence(.sick, for: CrewMember.youID)],
            on: date
        )
        XCTAssertEqual(merged?.dayTypeID, .sick)
        XCTAssertEqual(merged?.shifts, [])
    }

    func testATypeYouChoseYourselfIsNeverOverwritten() {
        let mine = DayRecord(date: date, dayTypeID: .vacation)
        let merged = SiteCalendarSync.merged(
            personal: mine,
            siteDays: [siteDay().settingAbsence(.sick, for: CrewMember.youID)],
            on: date
        )
        XCTAssertEqual(merged?.dayTypeID, .vacation)
    }

    func testHoursOfYourOwnKeepTheDayAWorkingDay() {
        let mine = DayRecord(date: date, shifts: [Shift(start: Fixture.time(18), end: Fixture.time(20))])
        let merged = SiteCalendarSync.merged(
            personal: mine,
            siteDays: [siteDay().settingAbsence(.sick, for: CrewMember.youID)],
            on: date
        )
        XCTAssertNil(merged?.dayTypeID)
    }

    func testPresentOnAnotherSiteKeepsTheDayAWorkingDay() {
        let other = SiteDay(
            siteID: UUID(), date: date, start: Fixture.time(7), end: Fixture.time(12),
            present: [Attendance(memberID: CrewMember.youID)]
        )
        let merged = SiteCalendarSync.merged(
            personal: nil,
            siteDays: [siteDay().settingAbsence(.sick, for: CrewMember.youID), other],
            on: date
        )
        XCTAssertNil(merged?.dayTypeID)
        XCTAssertEqual(merged?.shifts.count, 1)
    }

    func testTakingTheReasonBackTakesTheTypeItPutOn() {
        let before = siteDay().settingAbsence(.sick, for: CrewMember.youID)
        let typed = SiteCalendarSync.merged(personal: nil, siteDays: [before], on: date)
        XCTAssertEqual(typed?.dayTypeID, .sick)

        let cleared = SiteCalendarSync.merged(
            personal: typed,
            siteDays: [before.settingAbsence(nil, for: CrewMember.youID)],
            on: date,
            previousSiteDays: [before]
        )
        XCTAssertNil(cleared, "nothing else was on the day")

        // Changing the reason changes the type.
        let changed = SiteCalendarSync.merged(
            personal: typed,
            siteDays: [before.settingAbsence(.vacation, for: CrewMember.youID)],
            on: date,
            previousSiteDays: [before]
        )
        XCTAssertEqual(changed?.dayTypeID, .vacation)

        // Ticking yourself back in: hours, and no type.
        let ticked = SiteCalendarSync.merged(
            personal: typed,
            siteDays: [before.togglingPresence(of: CrewMember.youID)],
            on: date,
            previousSiteDays: [before]
        )
        XCTAssertNil(ticked?.dayTypeID)
        XCTAssertEqual(ticked?.shifts.count, 1)
    }

    func testTakingTheReasonBackLeavesATypeYouChoseAlone() {
        let before = siteDay().settingAbsence(.sick, for: CrewMember.youID)
        let mine = DayRecord(date: date, dayTypeID: .vacation)
        let merged = SiteCalendarSync.merged(
            personal: mine,
            siteDays: [before.settingAbsence(nil, for: CrewMember.youID)],
            on: date,
            previousSiteDays: [before]
        )
        XCTAssertEqual(merged?.dayTypeID, .vacation)
    }

    // MARK: - The site sheet

    private let site = Site(name: "Trg Pravde")

    private func sheet(
        crew: [CrewMember],
        days: [SiteDay],
        language: ExportLanguage = .english,
        settings: AppSettings? = nil
    ) -> ReportTable {
        var settings = settings ?? Fixture.settings()
        settings.export = ExportPreferences(language: language, ownerName: "Marijo")
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(
                site: site,
                crew: crew,
                results: days.map(calculator.compute),
                range: CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
            )
    }

    private func onSite(_ day: Int, present: [UUID], absences: [CrewAbsence] = []) -> SiteDay {
        SiteDay(
            siteID: site.id, date: Fixture.date(2026, 8, day), start: Fixture.time(7), end: Fixture.time(16),
            breakMinutes: 30, present: present.map { Attendance(memberID: $0) }, absences: absences
        )
    }

    func testAnAbsentPersonsCellSaysWhy() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            onSite(4, present: [CrewMember.youID, ana.id])
        ])
        // Day, you (2), Ana (2), Notes.
        XCTAssertEqual(t.rows[0].values[3], "Sick leave")
        XCTAssertEqual(t.rows[0].values[4], "")
        XCTAssertNil(t.rows[0].minutes[4])
        XCTAssertEqual(t.rows[0].mergedGroups, [2], "one cell across the person's group, as a dash is")
    }

    func testTheReasonIsInTheSheetsLanguage() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let ivo = CrewMember(siteID: site.id, name: "Ivo", sortOrder: 1)
        let days = [onSite(3, present: [CrewMember.youID], absences: [
            CrewAbsence(memberID: ana.id, dayTypeID: .sick),
            CrewAbsence(memberID: ivo.id, dayTypeID: .vacation)
        ])]
        let german = sheet(crew: [ana, ivo], days: days, language: .german)
        XCTAssertEqual(german.rows[0].values[3], "Krankheit")
        XCTAssertEqual(german.rows[0].values[5], "Urlaub")
        let croatian = sheet(crew: [ana, ivo], days: days, language: .croatian)
        XCTAssertEqual(croatian.rows[0].values[3], "Bolovanje")
        XCTAssertEqual(croatian.rows[0].values[5], "Godišnji odmor")
    }

    /// Sick all month is still on the sheet: the director needs to see it.
    func testSomeoneAbsentAllMonthStillHasAColumn() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])
        ])
        XCTAssertEqual(t.columnGroups.map(\.title), ["Day", "Marijo", "Ana", "Notes"])
    }

    func testSickAndLeaveDaysAreCountedUnderTheTotals() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let ivo = CrewMember(siteID: site.id, name: "Ivo", sortOrder: 1)
        let t = sheet(crew: [ana, ivo], days: [
            onSite(3, present: [CrewMember.youID, ivo.id], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            onSite(4, present: [CrewMember.youID, ivo.id], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            onSite(5, present: [CrewMember.youID], absences: [
                CrewAbsence(memberID: ana.id, dayTypeID: .vacation),
                CrewAbsence(memberID: ivo.id, dayTypeID: .personal)
            ]),
            onSite(6, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ivo.id, dayTypeID: .dayOff)])
        ])
        XCTAssertEqual(t.trailingSummaryRows, 4)
        let sick = t.rows[t.rows.count - 2]
        let leave = t.rows[t.rows.count - 1]
        XCTAssertEqual(sick.role, .count)
        XCTAssertEqual(sick.values[0], "Sick days")
        XCTAssertEqual(sick.values[2], "", "nothing for someone with none")
        XCTAssertEqual(sick.values[4], "2")
        XCTAssertEqual(sick.values[6], "")
        XCTAssertEqual(leave.values[0], "Leave days")
        XCTAssertEqual(leave.values[4], "1")
        XCTAssertEqual(leave.values[6], "1", "a personal day is leave; a day off is not")
        // Days worked are still days worked.
        XCTAssertEqual(t.rows[t.rows.count - 3].values[0], "Days worked")
        XCTAssertEqual(t.rows[t.rows.count - 3].values[6], "2")
    }

    func testNoRowsForSickOrLeaveWhenNobodyHadAny() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .dayOff)])
        ])
        XCTAssertEqual(t.trailingSummaryRows, 2)
        XCTAssertEqual(t.rows.last?.values[0], "Days worked")
    }

    func testOnlyTheRowThatHasDaysAppears() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)])
        ])
        XCTAssertEqual(t.trailingSummaryRows, 3)
        XCTAssertEqual(t.rows.last?.values[0], "Leave days")
    }

    func testTheCountRowsInGermanAndCroatian() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let days = [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)]),
            onSite(4, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .vacation)])
        ]
        let german = sheet(crew: [ana], days: days, language: .german)
        XCTAssertEqual(german.rows.suffix(2).map { $0.values[0] }, ["Krankheitstage", "Urlaubstage"])
        let croatian = sheet(crew: [ana], days: days, language: .croatian)
        XCTAssertEqual(croatian.rows.suffix(2).map { $0.values[0] }, ["Dani bolovanja", "Dani dopusta"])
    }

    /// The workbook's month total still adds up the days only.
    func testTheWorkbookTotalStopsAtTheLastDay() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID, ana.id]),
            onSite(4, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: .sick)])
        ])
        let package = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(package.contains(">Sick days<"))
        XCTAssertTrue(package.contains(">Sick leave<"))
        // Two days, so the sum covers two rows and never the counts below.
        let sum = try? XCTUnwrap(package.range(of: #"SUM\(C(\d+):C(\d+)\)"#, options: .regularExpression))
        let formula = sum.map { String(package[$0]) } ?? ""
        let rows = formula.dropFirst(4).dropLast().split(separator: ":").compactMap { Int($0.dropFirst()) }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual((rows.last ?? 0) - (rows.first ?? 0), 1)
    }

    /// A custom type keeps the name it was given, in every language.
    func testACustomReasonPrintsItsOwnName() {
        let ana = CrewMember(siteID: site.id, name: "Ana")
        var settings = Fixture.settings()
        settings.customDayTypes = [DayTypeDefinition(
            id: DayTypeID("training"), name: "Schulung", symbolName: "book", tint: .green,
            expectation: .creditedAbsence, showsTimesByDefault: false
        )]
        let t = sheet(crew: [ana], days: [
            onSite(3, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ana.id, dayTypeID: DayTypeID("training"))])
        ], language: .croatian, settings: settings)
        XCTAssertEqual(t.rows[0].values[3], "Schulung")
        XCTAssertEqual(t.rows.last?.values[0], "Dani dopusta", "a custom absence is leave")
    }
}
