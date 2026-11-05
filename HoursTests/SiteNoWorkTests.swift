import XCTest
@testable import Hours

/// Days nobody worked on a site (2026-11-05): the crew on another of your
/// sites, a day recorded as "no work" for a reason, and a paused site. None
/// of them reads as "not written", and the reminders leave them alone.
final class SiteNoWorkTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let october = YearMonth(year: 2026, month: 10)
    /// Friday 23 October 2026.
    private let today = Fixture.date(2026, 10, 23)
    private let jarunski = UUID()
    private let trg = UUID()
    private let weekdays = SiteSetup(workDays: [2, 3, 4, 5, 6])

    private func d(_ day: Int) -> CalendarDate { Fixture.date(2026, 10, day) }

    // The owner's sites: Ana and Ivo on both crews, matched by name.
    private let ana = UUID(), ivo = UUID(), anaThere = UUID(), ivoThere = UUID()

    private var members: [CrewMember] {
        [
            CrewMember(id: ana, siteID: jarunski, name: "Ana"),
            CrewMember(id: ivo, siteID: jarunski, name: "Ivo"),
            CrewMember(id: anaThere, siteID: trg, name: "Ana"),
            CrewMember(id: ivoThere, siteID: trg, name: "Ivo"),
        ]
    }

    private func worked(_ site: UUID, _ day: Int, _ people: [UUID]) -> SiteDay {
        SiteDay(
            siteID: site, date: d(day), start: Fixture.time(7), end: Fixture.time(15), breakMinutes: 30,
            present: people.map { Attendance(memberID: $0) }
        )
    }

    private func statuses(_ days: [SiteDay], setup: SiteSetup? = nil) -> [CalendarDate: SiteDayStatus] {
        let check = SiteMonthOverview.crew(siteID: jarunski, members: members, siteDays: days, month: october, calendar: calendar)
        return SiteDayStatus.month(
            october, siteID: jarunski, siteDays: days, setup: setup ?? weekdays, check: check,
            today: today, calendar: calendar
        )
    }

    /// Jarunski worked on the 19th by you, Ana and Ivo; the 20th–22nd the
    /// three of you were on Trg Pravde.
    private var owner: [SiteDay] {
        [worked(jarunski, 19, [CrewMember.youID, ana, ivo])]
            + [20, 21, 22].map { worked(trg, $0, [CrewMember.youID, anaThere, ivoThere]) }
    }

    // MARK: - 1. The crew was elsewhere

    func testADayEveryoneWasOnAnotherSiteIsNotMissing() {
        let month = statuses(owner)
        XCTAssertEqual(month[d(20)], .elsewhere)
        XCTAssertEqual(month[d(21)], .elsewhere)
        XCTAssertEqual(month[d(22)], .elsewhere)
        XCTAssertEqual(month[d(16)], .missing, "before anyone appeared here, nobody is expected: as before")
        XCTAssertEqual(SiteDayStatus.missingCount(in: month.filter { $0.key >= d(19) }), 0)
    }

    func testTheHeadlineDoesNotCountThem() {
        let days = owner.filter { $0.date >= d(19) } + [worked(jarunski, 1, [CrewMember.youID, ana, ivo])]
        let month = statuses(days).filter { $0.key >= d(19) }
        XCTAssertEqual(SiteMonthOverview.headline(month), .allWritten)
        XCTAssertFalse(SiteMonthOverview.strip(month).contains { $0.status == .elsewhere }, "drawn like a day off")
    }

    func testOnlySomeOfTheCrewElsewhereStaysMissing() {
        let days = [worked(jarunski, 19, [CrewMember.youID, ana, ivo]), worked(trg, 20, [CrewMember.youID, anaThere])]
        let month = statuses(days)
        XCTAssertEqual(month[d(20)], .missing, "Ivo is not accounted for")
        let check = SiteMonthOverview.crew(siteID: jarunski, members: members, siteDays: days, month: october, calendar: calendar)
        XCTAssertTrue(check.isPartlyElsewhere(on: d(20)))
        XCTAssertFalse(check.isAllElsewhere(on: d(20)))
    }

    func testAReasonOnAnotherSiteAccountsForSomeoneToo() {
        let days = [
            worked(jarunski, 19, [CrewMember.youID, ana, ivo]),
            worked(trg, 20, [CrewMember.youID, anaThere]).settingAbsence(.sick, for: ivoThere),
        ]
        XCTAssertEqual(statuses(days)[d(20)], .elsewhere)
    }

    func testWithNoCrewTheOldRuleStays() {
        let check = SiteCrewCheck(joined: [:])
        XCTAssertFalse(check.isAllElsewhere(on: d(20)))
        XCTAssertEqual(
            SiteDayStatus.month(october, siteID: jarunski, siteDays: [], setup: weekdays, crew: [], today: today, calendar: calendar)[d(20)],
            .missing
        )
    }

    func testTodayWithTheCrewElsewhereIsNotOpen() {
        let days = owner + [worked(trg, 23, [CrewMember.youID, anaThere, ivoThere])]
        XCTAssertEqual(statuses(days)[d(23)], .elsewhere)
        XCTAssertTrue(SiteMonthOverview.isCrewElsewhere(siteID: jarunski, on: d(23), members: members, siteDays: days, calendar: calendar))
        XCTAssertFalse(SiteMonthOverview.isCrewElsewhere(siteID: trg, on: d(23), members: members, siteDays: days, calendar: calendar))
    }

    func testAWrittenDayIsWrittenWhateverTheOtherSitesSay() {
        let days = owner + [worked(jarunski, 20, [CrewMember.youID])]
        XCTAssertNotEqual(statuses(days)[d(20)], .elsewhere)
    }

    // MARK: - 2. "No work" for a reason

    func testANoWorkDayIsNeitherMissingNorWritten() {
        let day = SiteDay.noWork(.noWork, siteID: jarunski, date: d(16), jobID: nil)
        let month = statuses(owner + [day])
        XCTAssertEqual(month[d(16)], .noWork)
        XCTAssertFalse(day.isBlank, "it is stored")
        XCTAssertTrue(day.present.isEmpty)
        XCTAssertNil(day.start)
        XCTAssertEqual(SiteMonthOverview.headline(month.filter { $0.key >= d(16) }), .allWritten)
    }

    func testTheCountDrops() {
        let before = statuses([])
        let missing = SiteDayStatus.missingCount(in: before)
        let marked = SiteDay.noWork(.dayOff, siteID: jarunski, date: d(21), jobID: nil)
        XCTAssertEqual(SiteDayStatus.missingCount(in: statuses([marked])), missing - 1)
        XCTAssertEqual(SiteMonthOverview.headline(statuses([marked])), .notWritten(missing - 1))
    }

    func testBadWeatherIsTheFullStopOfTheUsualDay() {
        let usual = worked(jarunski, 21, [CrewMember.youID, ana])
        let day = SiteDay.noWork(.badWeather, siteID: jarunski, date: d(21), jobID: nil, usual: usual)
        XCTAssertTrue(day.isBadWeatherStop)
        XCTAssertTrue(day.isFullStop(for: CrewMember.youID), "your own day gets Bad weather, as the stop does")
        XCTAssertEqual(day.present.map(\.memberID), [CrewMember.youID, ana])
        XCTAssertNil(day.start)
        XCTAssertTrue(day.isNoWorkDay)
        XCTAssertEqual(statuses([day])[d(21)], .noWork)
        XCTAssertEqual(SiteDayCalculator(settings: Fixture.settings(), calendar: calendar).compute(day).crewTotalMinutes, 0)
    }

    func testUndoLeavesNothing() {
        for reason in SiteNoWorkReason.allCases {
            let usual = worked(jarunski, 21, [CrewMember.youID, ana])
            let day = SiteDay.noWork(reason, siteID: jarunski, date: d(21), jobID: nil, usual: usual)
            XCTAssertTrue(day.clearingNoWork().isBlank, "\(reason)")
        }
        let rained = SiteDay.noWork(.badWeather, siteID: jarunski, date: d(21), jobID: nil, usual: worked(jarunski, 21, [ana]))
        XCTAssertTrue(rained.liftingBadWeatherStop().isBlank, "the weather row's Undo does the same")
    }

    func testUndoKeepsANoteWrittenSince() {
        var day = SiteDay.noWork(.noWork, siteID: jarunski, date: d(21), jobID: nil)
        day.note = "Waiting for the plasterers"
        let undone = day.clearingNoWork()
        XCTAssertFalse(undone.isBlank)
        XCTAssertNil(undone.noWork)
    }

    func testTickingSomeoneMakesItAnOrdinaryDayAgain() {
        let day = SiteDay.noWork(.dayOff, siteID: jarunski, date: d(21), jobID: nil).togglingPresence(of: ana)
        XCTAssertNil(day.noWork)
        XCTAssertFalse(day.isNoWorkDay)
        var stale = SiteDay.noWork(.dayOff, siteID: jarunski, date: d(21), jobID: nil)
        stale.present = [Attendance(memberID: ana)]
        XCTAssertFalse(stale.isNoWorkDay, "a stray marker on a day someone worked counts for nothing")
    }

    func testTheReasonsAreOfferedWithTheCrewElsewhereFirstWhenItIsTrue() {
        XCTAssertEqual(SiteNoWorkReason.offered(someoneElsewhere: true).first, .crewElsewhere)
        XCTAssertEqual(SiteNoWorkReason.offered(someoneElsewhere: false).first, .noWork)
        XCTAssertEqual(Set(SiteNoWorkReason.offered(someoneElsewhere: false)), Set(SiteNoWorkReason.allCases))
    }

    func testTheSheetListsTheMonthsMissingDays() {
        let days = [worked(jarunski, 19, [CrewMember.youID, ana, ivo]), worked(trg, 20, [CrewMember.youID, anaThere])]
        let check = SiteMonthOverview.crew(siteID: jarunski, members: members, siteDays: days, month: october, calendar: calendar)
        let listed = SiteNoWorkSheet.days(statuses: statuses(days), month: october, check: check)
        XCTAssertEqual(listed.map(\.date), SiteDayStatus.missingDays(in: statuses(days)))
        XCTAssertEqual(listed.first { $0.date == d(20) }?.someoneElsewhere, true)
        XCTAssertEqual(listed.first { $0.date == d(21) }?.someoneElsewhere, false)
    }

    // MARK: - Stored without a new column

    func testTheReasonRidesInTheAbsenceColumn() {
        let absence = CrewAbsence(memberID: ana, dayTypeID: .sick)
        let data = SiteDayStorage.absenceData(absences: [absence], moves: [], noWork: .dayOff, siteID: jarunski)
        XCTAssertEqual(SiteDayStorage.noWork(fromAbsenceData: data), .dayOff)
        XCTAssertEqual(CrewAbsence.decodeList(data), [absence], "a reader of the reasons leaves it out")
        XCTAssertTrue(SiteDayStorage.moves(fromAbsenceData: data).isEmpty)
        XCTAssertNotNil(SiteDayStorage.absenceData(absences: [], moves: [], noWork: .noWork, siteID: jarunski))
        XCTAssertNil(SiteDayStorage.absenceData(absences: [], moves: []))
    }

    func testAnOlderReaderOfTheColumnSkipsTheEntry() throws {
        let data = try XCTUnwrap(SiteDayStorage.absenceData(absences: [], moves: [], noWork: .noWork, siteID: jarunski))
        // 1.1's reader: every entry a person and a day type, entry by entry.
        struct OldEntry: Decodable { var memberID: UUID; var dayTypeID: String }
        struct Lossy: Decodable {
            var value: OldEntry?
            init(from decoder: Decoder) throws { value = try? OldEntry(from: decoder) }
        }
        let read = try JSONDecoder().decode([Lossy].self, from: data)
        XCTAssertTrue(read.compactMap(\.value).isEmpty)
    }

    func testAnUnknownReasonReadsAsNone() {
        let json = #"[{"memberID":"\#(jarunski.uuidString)","kind":"noWork","reason":"strike"}]"#
        XCTAssertNil(SiteDayStorage.noWork(fromAbsenceData: Data(json.utf8)))
    }

    func testABackupCarriesTheReasonAndOldOnesStillRestore() throws {
        let site = Site(name: "Jarunski Dvori")
        let day = SiteDay.noWork(.crewElsewhere, siteID: site.id, date: d(21), jobID: nil)
        let archive = BackupArchive(settings: AppSettings(), days: [], holidays: [], sites: [site], crew: [], siteDays: [day])
        let decoded = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(decoded.siteDays?.first?.noWork, .crewElsewhere)

        let plain = String(decoding: try JSONEncoder().encode(worked(site.id, 20, [ana])), as: UTF8.self)
        XCTAssertFalse(plain.contains("noWork"), "written only when set")

        let old = """
        {"siteID": "\(site.id.uuidString)", "date": 20261021, "breakMinutes": 0, "present": [], "note": ""}
        """
        XCTAssertNil(try JSONDecoder().decode(SiteDay.self, from: Data(old.utf8)).noWork)
    }

    // MARK: - Sheets

    func testTheSheetSaysNoWorkAndWhy() {
        let english = ExportLanguage.english
        XCTAssertEqual(SiteDay.noWork(.dayOff, siteID: jarunski, date: d(21), jobID: nil).sheetLead(in: english), "No work · Day off")
        XCTAssertEqual(SiteDay.noWork(.noWork, siteID: jarunski, date: d(21), jobID: nil).sheetLead(in: english), "No work")
        XCTAssertEqual(
            SiteDay.noWork(.crewElsewhere, siteID: jarunski, date: d(21), jobID: nil).sheetLead(in: .german),
            "Keine Arbeit · Kolonne auf anderer Baustelle"
        )
        let rained = SiteDay.noWork(.badWeather, siteID: jarunski, date: d(21), jobID: nil, usual: worked(jarunski, 21, [ana]))
        XCTAssertEqual(rained.sheetLead(in: english), "No work · Bad weather")
        XCTAssertEqual(worked(jarunski, 21, [ana]).stoppedForBadWeather(at: nil).sheetLead(in: english), "Bad weather", "as before")
        var noted = SiteDay.noWork(.noWork, siteID: jarunski, date: d(21), jobID: nil)
        noted.note = "No material"
        XCTAssertEqual(noted.sheetNote(in: english), "No work · No material")
        XCTAssertEqual(worked(jarunski, 21, [ana]).sheetNote(in: english), "")
    }

    func testTheSiteSheetPrintsIt() {
        var settings = Fixture.settings()
        settings.export.language = .english
        let site = Site(name: "Jarunski Dvori")
        let days = [
            worked(site.id, 20, [CrewMember.youID]),
            SiteDay.noWork(.dayOff, siteID: site.id, date: d(21), jobID: nil),
        ]
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let table = SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(site: site, crew: [], results: days.map(calculator.compute), range: october.range(in: calendar))
        XCTAssertTrue(table.rows.contains { $0.values.last == "No work · Day off" })
    }

    // MARK: - 3. A paused site

    func testNothingIsExpectedWhilePaused() {
        let paused = SiteSetup(workDays: [2, 3, 4, 5, 6], pause: SitePause(start: d(19), end: d(21)))
        XCTAssertFalse(SiteWorkDays.expects(jarunski, on: d(19), setup: paused, siteDays: [], calendar: calendar))
        XCTAssertFalse(SiteWorkDays.expects(jarunski, on: d(21), setup: paused, siteDays: [], calendar: calendar), "the until date is inclusive")
        XCTAssertTrue(SiteWorkDays.expects(jarunski, on: d(22), setup: paused, siteDays: [], calendar: calendar))
        XCTAssertTrue(SiteWorkDays.expects(jarunski, on: d(16), setup: paused, siteDays: [], calendar: calendar))
    }

    func testAnOpenEndedPauseLastsUntilTurnedOff() {
        let paused = SiteSetup(workDays: [2, 3, 4, 5, 6], pause: SitePause(start: d(19)))
        XCTAssertFalse(SiteWorkDays.expects(jarunski, on: Fixture.date(2027, 3, 1), setup: paused, siteDays: [], calendar: calendar))
        let month = statuses([], setup: paused)
        XCTAssertEqual(month[d(20)], .dayOff, "drawn neutral")
        XCTAssertEqual(month[d(16)], .missing)
        XCTAssertEqual(SiteMonthOverview.headline(month, pause: paused.pause, today: today), .paused(until: nil))
        XCTAssertEqual(
            SiteMonthOverview.headline(month, pause: SitePause(start: d(19), end: d(30)), today: today),
            .paused(until: d(30))
        )
        XCTAssertEqual(SiteMonthOverview.headline(month, pause: SitePause(start: d(26)), today: today), .notWritten(SiteDayStatus.missingCount(in: month)))
    }

    func testADayWrittenDuringAPauseCountsAsAnyOther() {
        let paused = SiteSetup(workDays: [2, 3, 4, 5, 6], pause: SitePause(start: d(19)))
        let month = statuses([worked(jarunski, 20, [CrewMember.youID])], setup: paused)
        XCTAssertEqual(month[d(20)], .written)
    }

    func testAnEndBeforeTheStartIsTheStartsDay() {
        let pause = SitePause(start: d(20), end: d(10))
        XCTAssertEqual(pause.end, d(20))
        XCTAssertTrue(pause.contains(d(20)))
        XCTAssertFalse(pause.contains(d(21)))
    }

    func testThePauseIsKeptOnlyWhenSetAndOldSettingsRead() throws {
        let plain = String(decoding: try JSONEncoder().encode(SiteSetup(workDays: [2])), as: UTF8.self)
        XCTAssertFalse(plain.contains("pause"))
        XCTAssertTrue(SiteSetup().isStandard)
        XCTAssertFalse(SiteSetup(pause: SitePause(start: d(20))).isStandard)

        let setup = SiteSetup(workDays: [2], pause: SitePause(start: d(20), end: d(30)))
        let decoded = try JSONDecoder().decode(SiteSetup.self, from: JSONEncoder().encode(setup))
        XCTAssertEqual(decoded, setup)

        let damaged = #"{"workDays":[2],"pause":{"end":20261030}}"#
        XCTAssertNil(try JSONDecoder().decode(SiteSetup.self, from: Data(damaged.utf8)).pause, "no start, no pause")
    }

    func testABackupCarriesThePause() throws {
        var settings = AppSettings()
        settings.setSiteSetup(SiteSetup(pause: SitePause(start: d(20))), for: jarunski)
        let archive = BackupArchive(settings: settings, days: [], holidays: [])
        let decoded = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(decoded.settings.siteSetup(for: jarunski).pause, SitePause(start: d(20)))
    }

    // MARK: - Reminders

    func testTheEveningReminderSkipsPausedSitesAndCrewElsewhere() {
        let days = [SiteDay(siteID: jarunski, date: d(16))]
        let setup: [UUID: Set<Int>] = [jarunski: [2, 3, 4, 5, 6]]
        let all = SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar, workDays: setup)
        XCTAssertTrue(all.contains(today))

        let paused = SiteReminderPlan.dates(
            siteDays: days, today: today, calendar: calendar, workDays: setup,
            pauses: [jarunski: SitePause(start: today, end: d(27))]
        )
        XCTAssertFalse(paused.contains(today))
        XCTAssertFalse(paused.contains(d(27)), "until inclusive")
        XCTAssertTrue(paused.contains(d(28)))

        let elsewhere = SiteReminderPlan.dates(
            siteDays: days, today: today, calendar: calendar, workDays: setup, crewElsewhere: [jarunski: [today]]
        )
        XCTAssertFalse(elsewhere.contains(today))
        XCTAssertTrue(elsewhere.contains(d(26)))
    }

    func testArrivingAtAPausedSiteAsksNothing() {
        var site = Site(name: "Jarunski Dvori")
        site.place = SitePlace(latitude: 45.78, longitude: 15.93)
        site.remindsOnArrival = true
        let day = Fixture.engine().day(Fixture.workingTuesday, record: nil, holidays: [])
        for event in ArrivalEvent.allCases {
            XCTAssertEqual(
                ArrivalReminderPolicy.decide(
                    event, site: site, today: day, isClockRunning: event == .left,
                    isPaused: true, log: ArrivalReminderLog(), now: Date()
                ),
                .quiet(.paused)
            )
        }
    }
}
