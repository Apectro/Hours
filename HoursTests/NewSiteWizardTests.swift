import XCTest
@testable import Hours

/// The new-site wizard's engine (1.2): a site's usual day and extras
/// (`SiteSetup`), what new sites start with (`NewSiteDefaults`), copying a
/// site's setup (`SiteBlueprint`), the names typed one per line
/// (`NameList`) and the crew picked from other sites (`CrewPicking`).
final class NewSiteWizardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zagreb")!
        calendar.firstWeekday = 2
        return calendar
    }

    private let seven = TimeOfDay(hour: 7, minute: 0)
    private let half3 = TimeOfDay(hour: 15, minute: 30)

    // MARK: - Usual-day defaults

    /// Nothing chosen under "New sites start with": the working week's own
    /// start, end and break, and the days it has hours on.
    func testNewSitesStartWithTheWorkingWeekUntilSomethingIsChosen() {
        let schedule = WorkSchedule(defaultStart: seven, defaultEnd: half3, defaultBreakMinutes: 30)

        let setup = NewSiteDefaults().setup(schedule: schedule)

        XCTAssertEqual(setup.start, seven)
        XCTAssertEqual(setup.end, half3)
        XCTAssertEqual(setup.breakMinutes, 30)
        XCTAssertEqual(setup.workDays, [2, 3, 4, 5, 6], "Monday to Friday")
        XCTAssertTrue(setup.asksKilometres)
        XCTAssertTrue(setup.eveningReminder)
        XCTAssertTrue(setup.monthlySheet)
        XCTAssertTrue(setup.keepsDiary)
    }

    func testWhatIsChosenWinsOverTheWorkingWeek() {
        var defaults = NewSiteDefaults()
        defaults.start = TimeOfDay(hour: 6, minute: 30)
        defaults.end = TimeOfDay(hour: 17, minute: 0)
        defaults.breakMinutes = 45
        defaults.workDays = [2, 3, 4, 5, 6, 7]
        defaults.asksKilometres = false
        defaults.eveningReminder = false
        defaults.monthlySheet = false

        let setup = defaults.setup(schedule: WorkSchedule())

        XCTAssertEqual(setup.start, TimeOfDay(hour: 6, minute: 30))
        XCTAssertEqual(setup.end, TimeOfDay(hour: 17, minute: 0))
        XCTAssertEqual(setup.breakMinutes, 45)
        XCTAssertEqual(setup.workDays, [2, 3, 4, 5, 6, 7])
        XCTAssertFalse(setup.asksKilometres)
        XCTAssertFalse(setup.eveningReminder)
        XCTAssertFalse(setup.monthlySheet)
    }

    /// A week with no working day at all would make a site nobody is ever
    /// expected on; it falls back to Monday to Friday.
    func testAWeekWithNoWorkingDaysFallsBackToMondayToFriday() {
        let schedule = WorkSchedule(minutesByWeekday: [0, 0, 0, 0, 0, 0, 0])

        XCTAssertEqual(NewSiteDefaults().setup(schedule: schedule).workDays, [2, 3, 4, 5, 6])
    }

    func testFreshBlueprintTakesTheDefaultsAndNoCrew() {
        var defaults = NewSiteDefaults()
        defaults.allowanceByDefault = true
        let schedule = WorkSchedule(defaultStart: seven, defaultEnd: half3, defaultBreakMinutes: 30)
        let job = UUID()

        let blueprint = SiteBlueprint.fresh(defaults: defaults, schedule: schedule, jobID: job)

        XCTAssertTrue(blueprint.allowanceByDefault)
        XCTAssertEqual(blueprint.jobID, job)
        XCTAssertEqual(blueprint.setup.start, seven)
        XCTAssertEqual(blueprint.crewNames, [])
    }

    // MARK: - Copying a site

    func testCopyingASiteTakesItsCrewTimesWorkDaysExtrasAndJob() {
        let job = UUID()
        let source = Site(name: "Hauptstraße 12", jobID: job, allowanceByDefault: true,
                          latitude: 45.8, longitude: 15.9, arrivalRadius: 300, remindsOnArrival: true,
                          address: "Hauptstraße 12, Berlin")
        var setup = SiteSetup(start: seven, end: half3, breakMinutes: 30, workDays: [2, 3, 4, 5, 6, 7])
        setup.asksKilometres = false
        setup.keepsDiary = false
        let crew = [
            CrewMember(siteID: source.id, name: "Ivan", sortOrder: 0),
            CrewMember(siteID: source.id, name: "Marko", sortOrder: 1),
            CrewMember(siteID: source.id, name: "Left Already", isHidden: true, sortOrder: 2),
        ]

        let blueprint = SiteBlueprint.copying(
            site: source, setup: setup, crew: crew, recentDays: [],
            calendar: calendar, fallback: SiteSetup()
        )

        XCTAssertEqual(blueprint.crewNames, ["Ivan", "Marko"], "hidden people have left the crew")
        XCTAssertEqual(blueprint.setup, setup)
        XCTAssertEqual(blueprint.jobID, job)
        XCTAssertTrue(blueprint.allowanceByDefault)

        // Not the name, the address or the place.
        let made = blueprint.make(name: "Trg Pravde", address: "", arrival: nil, sortOrder: 3)
        XCTAssertEqual(made.site.name, "Trg Pravde")
        XCTAssertEqual(made.site.address, "")
        XCTAssertNil(made.site.place)
        XCTAssertFalse(made.site.remindsOnArrival)
        XCTAssertEqual(made.site.arrivalRadius, Site.defaultArrivalRadius)
        XCTAssertNotEqual(made.site.id, source.id)
        XCTAssertEqual(made.site.sortOrder, 3)
        XCTAssertEqual(made.site.jobID, job)
        XCTAssertTrue(made.site.allowanceByDefault)
    }

    /// A site set up before usual days existed has none: its last day's
    /// times and the weekdays it was worked lately stand in.
    func testCopyingAnOlderSiteReadsItsUsualDayFromItsDays() {
        let source = Site(name: "Solarka")
        // Monday 19 and Tuesday 20 October 2026, and Thursday 22 the latest.
        let days = [
            SiteDay(siteID: source.id, date: CalendarDate(year: 2026, month: 10, day: 19), start: seven, end: half3, breakMinutes: 30),
            SiteDay(siteID: source.id, date: CalendarDate(year: 2026, month: 10, day: 20), start: seven, end: half3, breakMinutes: 30),
            SiteDay(siteID: source.id, date: CalendarDate(year: 2026, month: 10, day: 22),
                    start: TimeOfDay(hour: 6, minute: 0), end: TimeOfDay(hour: 14, minute: 0), breakMinutes: 20),
            // Another site's day says nothing about this one.
            SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 24), start: seven, end: half3),
        ]

        let blueprint = SiteBlueprint.copying(
            site: source, setup: SiteSetup(), crew: [], recentDays: days,
            calendar: calendar, fallback: SiteSetup(start: seven, end: half3, breakMinutes: 30, workDays: [2, 3, 4, 5, 6])
        )

        XCTAssertEqual(blueprint.setup.start, TimeOfDay(hour: 6, minute: 0), "the latest day's times")
        XCTAssertEqual(blueprint.setup.end, TimeOfDay(hour: 14, minute: 0))
        XCTAssertEqual(blueprint.setup.breakMinutes, 20)
        XCTAssertEqual(blueprint.setup.workDays, [2, 3, 5], "Monday, Tuesday and Thursday")
    }

    func testCopyingASiteWithNoDaysAtAllUsesTheFallback() {
        let source = Site(name: "Empty")
        let fallback = SiteSetup(start: seven, end: half3, breakMinutes: 30, workDays: [2, 3, 4, 5, 6])

        let blueprint = SiteBlueprint.copying(
            site: source, setup: SiteSetup(), crew: [], recentDays: [], calendar: calendar, fallback: fallback
        )

        XCTAssertEqual(blueprint.setup.start, seven)
        XCTAssertEqual(blueprint.setup.workDays, [2, 3, 4, 5, 6])
    }

    func testMakingASiteGivesEachPersonTheirOwnMemberInOrder() {
        var blueprint = SiteBlueprint.fresh(defaults: NewSiteDefaults(), schedule: WorkSchedule(), jobID: nil)
        blueprint.crewNames = ["Ivan", "Josip Kovač"]
        var arrival = Site(name: "", latitude: 45.81, longitude: 15.97, arrivalRadius: 300, remindsOnArrival: true)
        arrival.address = "ignored"

        let made = blueprint.make(name: "  Trg Pravde ", address: " Trg pravde 2\nZagreb ", arrival: arrival, sortOrder: 0)

        XCTAssertEqual(made.site.name, "Trg Pravde")
        XCTAssertEqual(made.site.address, "Trg pravde 2\nZagreb")
        XCTAssertEqual(made.site.place, SitePlace(latitude: 45.81, longitude: 15.97))
        XCTAssertEqual(made.site.arrivalRadius, 300)
        XCTAssertTrue(made.site.remindsOnArrival)
        XCTAssertEqual(made.crew.map(\.name), ["Ivan", "Josip Kovač"])
        XCTAssertEqual(made.crew.map(\.sortOrder), [0, 1])
        XCTAssertTrue(made.crew.allSatisfy { $0.siteID == made.site.id })
        XCTAssertEqual(made.setup, blueprint.setup)
    }

    /// "Create and set up another like it": a second site from the same
    /// blueprint has its own id and its own crew members.
    func testTwoSitesFromOneBlueprintShareNothingButTheSetup() {
        var blueprint = SiteBlueprint.fresh(defaults: NewSiteDefaults(), schedule: WorkSchedule(), jobID: nil)
        blueprint.crewNames = ["Ivan"]

        let first = blueprint.make(name: "A", address: "", arrival: nil, sortOrder: 0)
        let second = blueprint.make(name: "B", address: "", arrival: nil, sortOrder: 1)

        XCTAssertNotEqual(first.site.id, second.site.id)
        XCTAssertNotEqual(first.crew[0].id, second.crew[0].id)
        XCTAssertEqual(first.setup, second.setup)
    }

    // MARK: - Names, one per line

    func testNameListTrimsDropsBlankLinesAndDuplicates() {
        let text = "  Josip Kovač \n\nDario Marić\r\n josip  kovac\n\t\nAna"

        XCTAssertEqual(NameList.parse(text), ["Josip Kovač", "Dario Marić", "Ana"])
    }

    func testNameListSplitsOnCommasAndSemicolonsOnlyWhenThereAreNoLines() {
        XCTAssertEqual(NameList.parse("Ivan, Marko; Ana"), ["Ivan", "Marko", "Ana"])
        // A list pasted one per line keeps "Kovač, Josip" as one name.
        XCTAssertEqual(NameList.parse("Kovač, Josip\nMarić, Dario"), ["Kovač, Josip", "Marić, Dario"])
    }

    func testSpacesInsideANameAreTidied() {
        XCTAssertEqual(NameList.parse("Josip   Kovač"), ["Josip Kovač"])
    }

    func testANameIsTakenByAnySiteOfThatNameArchivedOrNot() {
        let sites = [Site(name: "Hauptstraße 12"), Site(name: "Solarka", isArchived: true)]

        XCTAssertTrue(NameList.isTaken("hauptstrasse 12 ", among: sites))
        XCTAssertTrue(NameList.isTaken("SOLARKA", among: sites))
        XCTAssertFalse(NameList.isTaken("Trg Pravde", among: sites))
        XCTAssertFalse(NameList.isTaken("   ", among: sites))
    }

    func testSeveralSitesAtOnceSplitsNewNamesFromTakenOnes() {
        let sites = [Site(name: "Solarka")]

        let split = NameList.newSites(from: "Trg Pravde\nsolarka\nVukovarska 5\ntrg pravde", among: sites)

        XCTAssertEqual(split.new, ["Trg Pravde", "Vukovarska 5"])
        XCTAssertEqual(split.taken, ["solarka"])
    }

    // MARK: - Crew from other sites

    func testCrewChoicesAreOnePerPersonWithWhereTheyWork() {
        let haupt = Site(name: "Hauptstraße 12", sortOrder: 0)
        let solarka = Site(name: "Solarka", sortOrder: 1)
        let old = Site(name: "Old", isArchived: true, sortOrder: 2)
        let crew = [
            CrewMember(siteID: haupt.id, name: "Ivan", sortOrder: 0),
            CrewMember(siteID: haupt.id, name: "Luka", sortOrder: 1),
            CrewMember(siteID: solarka.id, name: "luka", sortOrder: 0),
            CrewMember(siteID: solarka.id, name: "Tomasz", sortOrder: 1),
            CrewMember(siteID: solarka.id, name: "Gone", isHidden: true, sortOrder: 2),
            CrewMember(siteID: old.id, name: "Retired", sortOrder: 0),
        ]

        let choices = CrewPicking.choices(sites: [haupt, solarka, old], crew: crew)

        XCTAssertEqual(choices.map(\.name), ["Ivan", "Luka", "Tomasz"])
        XCTAssertEqual(choices.map(\.siteNames), [["Hauptstraße 12"], ["Hauptstraße 12", "Solarka"], ["Solarka"]])
    }

    func testMergingTickedAndTypedPeopleKeepsEachOnceTickedFirst() {
        let merged = CrewPicking.merge(ticked: ["Ivan", "Marko"], typed: ["Josip Kovač", "ivan", "Dario Marić"])

        XCTAssertEqual(merged, ["Ivan", "Marko", "Josip Kovač", "Dario Marić"])
    }

    func testYouAreNeverACrewMember() {
        XCTAssertEqual(CrewPicking.merge(ticked: [], typed: ["  ", ""]), [])
    }

    // MARK: - A site's setup in settings

    func testASiteWithNoSetupHasEverythingOnAndNoUsualDay() {
        let settings = AppSettings()
        let setup = settings.siteSetup(for: UUID())

        XCTAssertNil(setup.start)
        XCTAssertEqual(setup.workDays, [])
        XCTAssertTrue(setup.asksKilometres && setup.eveningReminder && setup.monthlySheet && setup.keepsDiary)
    }

    func testSetupsAndNewSiteDefaultsRoundTripThroughSettings() throws {
        let site = UUID()
        var settings = AppSettings()
        var setup = SiteSetup(start: seven, end: half3, breakMinutes: 30, workDays: [2, 3, 4, 5, 6])
        setup.monthlySheet = false
        settings.setSiteSetup(setup, for: site)
        settings.newSites.start = TimeOfDay(hour: 6, minute: 0)
        settings.newSites.allowanceByDefault = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.siteSetup(for: site), setup)
        XCTAssertEqual(decoded.newSites, settings.newSites)
        XCTAssertEqual(decoded, settings)
    }

    /// A backup carries them with the settings; one from before them reads
    /// as none.
    func testABackupCarriesSetupsAndAnOlderOneHasNone() throws {
        let site = UUID()
        var settings = AppSettings()
        settings.setSiteSetup(SiteSetup(start: seven, end: half3, breakMinutes: 30, workDays: [2, 3]), for: site)
        settings.newSites.eveningReminder = false

        let back = try BackupArchive.decoded(from: BackupArchive(settings: settings, days: [], holidays: []).encoded())

        XCTAssertEqual(back.settings.siteSetup(for: site), settings.siteSetup(for: site))
        XCTAssertFalse(back.settings.newSites.eveningReminder)

        let older = try BackupArchive.decoded(from: BackupArchive(settings: AppSettings(), days: [], holidays: []).encoded())
        XCTAssertEqual(older.settings.siteSetups, [:])
        XCTAssertEqual(older.settings.newSites, NewSiteDefaults())
    }

    /// Nothing set means nothing written, so settings without it are
    /// written exactly as before.
    func testUntouchedSetupsAreNotWritten() throws {
        var settings = AppSettings()
        settings.setSiteSetup(SiteSetup(), for: UUID())

        let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)

        XCTAssertFalse(json.contains("siteSetups"))
        XCTAssertFalse(json.contains("newSites"))
        XCTAssertEqual(settings.siteSetups, [:], "a setup with nothing in it is not kept")
    }

    /// One unreadable site's setup does not lose the others, and junk in a
    /// field falls back to its default.
    func testSetupsDecodeLeniently() throws {
        let good = UUID()
        let json = """
        {"siteSetups": {"\(good.uuidString)": {"start": 420, "end": 930, "breakMinutes": 30, "workDays": [2, 3], "monthlySheet": false},
                        "not-a-uuid": {"start": 420},
                        "\(UUID().uuidString)": "junk"},
         "newSites": {"start": "junk", "eveningReminder": false}}
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.siteSetup(for: good).start, seven)
        XCTAssertEqual(settings.siteSetup(for: good).workDays, [2, 3])
        XCTAssertFalse(settings.siteSetup(for: good).monthlySheet)
        XCTAssertEqual(settings.siteSetups.count, 1)
        XCTAssertNil(settings.newSites.start)
        XCTAssertFalse(settings.newSites.eveningReminder)
    }

    func testWorkDaysOutsideTheWeekAreDropped() throws {
        let json = #"{"workDays": [0, 2, 9, 7]}"#
        let setup = try JSONDecoder().decode(SiteSetup.self, from: Data(json.utf8))

        XCTAssertEqual(setup.workDays, [2, 7])
    }

    // MARK: - A new day starts with the usual times

    func testANewDayStartsWithTheSitesUsualTimes() {
        let day = SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 29))
        let setup = SiteSetup(start: seven, end: half3, breakMinutes: 30)

        let started = day.startingWithUsualTimes(of: setup)

        XCTAssertEqual(started.start, seven)
        XCTAssertEqual(started.end, half3)
        XCTAssertEqual(started.breakMinutes, 30)
    }

    func testADayWithTimesOfItsOwnKeepsThem() {
        let day = SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 29),
                          start: TimeOfDay(hour: 6, minute: 0), breakMinutes: 0)

        XCTAssertEqual(day.startingWithUsualTimes(of: SiteSetup(start: seven, end: half3, breakMinutes: 30)), day)
    }

    /// Unticking the last person on a day that only had the usual times
    /// takes them away again, so the day is blank and not kept.
    func testUntickingEveryoneTakesTheUsualTimesBack() {
        let setup = SiteSetup(start: seven, end: half3, breakMinutes: 30)
        let day = SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 29))
            .startingWithUsualTimes(of: setup)

        let emptied = day.droppingUnusedUsualTimes(of: setup)

        XCTAssertTrue(emptied.isBlank)
    }

    func testTimesOfItsOwnOrSomeoneThereAreKept() {
        let setup = SiteSetup(start: seven, end: half3, breakMinutes: 30)
        let date = CalendarDate(year: 2026, month: 10, day: 29)
        let changed = SiteDay(siteID: UUID(), date: date, start: TimeOfDay(hour: 6, minute: 0), end: half3, breakMinutes: 30)
        let someone = SiteDay(siteID: UUID(), date: date, start: seven, end: half3, breakMinutes: 30,
                              present: [Attendance(memberID: CrewMember.youID)])

        XCTAssertEqual(changed.droppingUnusedUsualTimes(of: setup), changed)
        XCTAssertEqual(someone.droppingUnusedUsualTimes(of: setup), someone)
    }

    func testASiteWithNoUsualTimesChangesNothing() {
        let day = SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 29))

        XCTAssertEqual(day.startingWithUsualTimes(of: SiteSetup()), day)
    }
}
