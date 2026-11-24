import XCTest
@testable import Hours

final class SiteReminderPlanTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Tuesday 2026-10-20.
    private let today = Fixture.date(2026, 10, 20)
    private let siteA = UUID()
    private let siteB = UUID()

    private func day(_ site: UUID, _ date: CalendarDate) -> SiteDay {
        SiteDay(siteID: site, date: date)
    }

    private func plan(_ days: [SiteDay]) -> [CalendarDate] {
        SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar)
    }

    func testNoRecentSiteWorkNoReminders() {
        XCTAssertEqual(plan([]), [])
        // 15 days back is outside the 14-day window.
        XCTAssertEqual(plan([day(siteA, today.adding(days: -15, in: calendar))]), [])
        // Today itself is not history.
        XCTAssertEqual(plan([day(siteA, today)]), [])
    }

    func testOnlyWeekdaysThatWereWorked() {
        // Monday 12th and Wednesday 14th.
        let result = plan([day(siteA, Fixture.date(2026, 10, 12)), day(siteA, Fixture.date(2026, 10, 14))])
        XCTAssertEqual(result, [Fixture.date(2026, 10, 21), Fixture.date(2026, 10, 26)])
    }

    func testTodayAlreadyRecordedIsSkipped() {
        // Worked last Tuesday (13th); today (Tuesday) is recorded.
        let result = plan([day(siteA, Fixture.date(2026, 10, 13)), day(siteA, today)])
        XCTAssertEqual(result, [])
    }

    func testTwoSitesOnDifferentWeekdaysRemindOnBoth() {
        let result = plan([day(siteA, Fixture.date(2026, 10, 12)), day(siteB, Fixture.date(2026, 10, 14))])
        XCTAssertEqual(result, [Fixture.date(2026, 10, 21), Fixture.date(2026, 10, 26)])
    }

    func testTodayStillReturnedWhenAnotherSiteIsMissing() {
        // Both sites work Tuesdays; only A is recorded today.
        let result = plan([
            day(siteA, Fixture.date(2026, 10, 13)),
            day(siteB, Fixture.date(2026, 10, 13)),
            day(siteA, today)
        ])
        XCTAssertEqual(result, [today])
    }

    func testASiteAskedWhenLeavingTodayGetsNoEveningReminderToday() {
        // Both sites work Tuesdays; neither is written today. The phone asked
        // about A as you left, so tonight's reminder is only for B; with both
        // asked, there is none tonight. Other days are untouched.
        let days = [
            day(siteA, Fixture.date(2026, 10, 13)), day(siteB, Fixture.date(2026, 10, 13)),
            day(siteA, Fixture.date(2026, 10, 14))
        ]
        let wednesday = Fixture.date(2026, 10, 21)
        XCTAssertEqual(
            SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar, askedWhenLeavingToday: [siteA]),
            [today, wednesday]
        )
        XCTAssertEqual(
            SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar, askedWhenLeavingToday: [siteA, siteB]),
            [wednesday]
        )
    }

    // MARK: - Which sites (2026-11)

    private func missing(_ days: [SiteDay], order: [UUID] = []) -> [SiteReminderPlan.Evening] {
        SiteReminderPlan.missing(siteDays: days, today: today, calendar: calendar, order: order)
    }

    /// Writing site A leaves the evening about site B, and says so.
    func testEachDateSaysWhichSitesAreMissing() {
        let days = [
            day(siteA, Fixture.date(2026, 10, 13)),
            day(siteB, Fixture.date(2026, 10, 13)),
            day(siteA, today)
        ]
        XCTAssertEqual(missing(days), [SiteReminderPlan.Evening(date: today, siteIDs: [siteB])])
        // Neither written: both, in the order asked for.
        let neither = Array(days.prefix(2))
        XCTAssertEqual(missing(neither, order: [siteB, siteA]).first?.siteIDs, [siteB, siteA])
        XCTAssertEqual(missing(neither, order: [siteA, siteB]).first?.siteIDs, [siteA, siteB])
        // A site the order does not know follows the ones it does.
        XCTAssertEqual(missing(neither, order: [siteB]).first?.siteIDs, [siteB, siteA])
    }

    func testTheDatesAreTheMissingEvenings() {
        let days = [day(siteA, Fixture.date(2026, 10, 12)), day(siteB, Fixture.date(2026, 10, 14))]
        XCTAssertEqual(missing(days).map(\.date), plan(days))
        XCTAssertEqual(missing(days).map(\.siteIDs), [[siteB], [siteA]])
        XCTAssertTrue(missing(days).allSatisfy { !$0.siteIDs.isEmpty })
    }

    func testWithoutAnOrderTheSitesComeById() {
        let days = [day(siteA, Fixture.date(2026, 10, 13)), day(siteB, Fixture.date(2026, 10, 13))]
        let expected = [siteA, siteB].sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(missing(days).first?.siteIDs, expected)
    }

    // MARK: - What the notification says

    func testOneSiteIsNamedAndOpened() {
        let evening = SiteReminderPlan.Evening(date: today, siteIDs: [siteB])
        let notice = SiteReminderNotice(evening, names: [siteA: "Trg Pravde", siteB: " Jarunski Dvori "])
        XCTAssertEqual(notice, .one(siteID: siteB, name: "Jarunski Dvori"))
        XCTAssertEqual(notice.link, .site(siteB))
    }

    func testTwoSitesAreBothNamedAndOpenTheSitesTab() {
        let evening = SiteReminderPlan.Evening(date: today, siteIDs: [siteB, siteA])
        let notice = SiteReminderNotice(evening, names: [siteA: "Trg Pravde", siteB: "Jarunski Dvori"])
        XCTAssertEqual(notice, .two(first: "Jarunski Dvori", second: "Trg Pravde"))
        XCTAssertEqual(notice.link, .sites)
    }

    func testMoreSitesAreCounted() {
        let third = UUID()
        let evening = SiteReminderPlan.Evening(date: today, siteIDs: [siteA, siteB, third])
        let notice = SiteReminderNotice(evening, names: [siteA: "A", siteB: "B", third: "C"])
        XCTAssertEqual(notice, .several(count: 3))
        XCTAssertEqual(notice.link, .sites)
    }

    func testASiteWithNoNameIsLeftOut() {
        let evening = SiteReminderPlan.Evening(date: today, siteIDs: [siteA, siteB])
        XCTAssertEqual(SiteReminderNotice(evening, names: [siteB: "B"]), .one(siteID: siteB, name: "B"))
        XCTAssertEqual(SiteReminderNotice(evening, names: [:]), .unnamed)
        XCTAssertEqual(SiteReminderNotice(evening, names: [siteA: "  "]).link, .sites)
    }

    // MARK: - From what is stored

    private let ana = UUID(), ivo = UUID(), anaThere = UUID(), ivoThere = UUID()

    private var members: [CrewMember] {
        [
            CrewMember(id: ana, siteID: siteA, name: "Ana"),
            CrewMember(id: ivo, siteID: siteA, name: "Ivo"),
            CrewMember(id: anaThere, siteID: siteB, name: "Ana"),
            CrewMember(id: ivoThere, siteID: siteB, name: "Ivo")
        ]
    }

    private func worked(_ site: UUID, _ date: CalendarDate, _ people: [UUID]) -> SiteDay {
        SiteDay(siteID: site, date: date, start: Fixture.time(7), end: Fixture.time(15),
                present: people.map { Attendance(memberID: $0) })
    }

    private func evenings(
        _ days: [SiteDay],
        setups: [UUID: SiteSetup] = [:],
        sites: [Site]? = nil,
        lastDays: [SiteDay] = []
    ) -> [SiteReminderPlan.Evening] {
        SiteReminderPlan.evenings(
            sites: sites ?? [Site(id: siteA, name: "A"), Site(id: siteB, name: "B", sortOrder: 1)],
            setup: { setups[$0] ?? SiteSetup() },
            members: members,
            siteDays: days,
            lastDays: lastDays,
            today: today,
            calendar: calendar,
            daysAhead: 1
        )
    }

    /// The owner's case: both sites are worked on Tuesdays by the same
    /// three people, by their history alone (no work days set). Before
    /// today's hours are saved both are missing; once site A is written
    /// with everyone on it, site B is not expected tonight.
    func testWritingOneSiteWithTheWholeCrewAnswersForTheOther() {
        let lastTuesday = Fixture.date(2026, 10, 13)
        let history = [
            worked(siteA, lastTuesday.adding(days: -1, in: calendar), [CrewMember.youID, ana, ivo]),
            worked(siteB, lastTuesday, [CrewMember.youID, anaThere, ivoThere]),
            worked(siteA, lastTuesday.adding(days: 1, in: calendar), [CrewMember.youID, ana, ivo])
        ]
        // Site A is inferred on Mondays and Wednesdays, site B on Tuesdays.
        XCTAssertEqual(evenings(history), [SiteReminderPlan.Evening(date: today, siteIDs: [siteB])])
        // Saved: site A today, with the three of you.
        let saved = history + [worked(siteA, today, [CrewMember.youID, ana, ivo])]
        XCTAssertEqual(evenings(saved), [], "site B asked for hours its whole crew wrote on site A")
    }

    func testSomeoneNotOnTheOtherSiteKeepsTheirSiteMissing() {
        let lastTuesday = Fixture.date(2026, 10, 13)
        let days = [
            worked(siteB, lastTuesday, [CrewMember.youID, anaThere, ivoThere]),
            worked(siteA, today, [CrewMember.youID, ana])
        ]
        XCTAssertEqual(evenings(days), [SiteReminderPlan.Evening(date: today, siteIDs: [siteB])], "Ivo may be on site B")
    }

    /// Work days set, and nobody there for three weeks: the window has no
    /// day to say who its crew is, so its last day does.
    func testASiteWithWorkDaysAndAnOldLastDayFollowsItsCrewToo() {
        let setups = [siteB: SiteSetup(workDays: [2, 3, 4, 5, 6])]
        let old = worked(siteB, Fixture.date(2026, 9, 29), [CrewMember.youID, anaThere, ivoThere])
        let todayOnA = worked(siteA, today, [CrewMember.youID, ana, ivo])
        XCTAssertEqual(
            evenings([todayOnA], setups: setups),
            [SiteReminderPlan.Evening(date: today, siteIDs: [siteB])],
            "with nothing to go by, the site stays expected"
        )
        XCTAssertEqual(evenings([todayOnA], setups: setups, lastDays: [old]), [])
        // The last day is who, not when: it never makes a weekday expected.
        XCTAssertEqual(evenings([], lastDays: [old]), [])
    }

    func testANewSiteWithWorkDaysAndNoDaysIsStillExpected() {
        let setups = [siteB: SiteSetup(workDays: [3])]
        XCTAssertEqual(
            evenings([worked(siteA, today, [CrewMember.youID, ana, ivo])], setups: setups),
            [SiteReminderPlan.Evening(date: today, siteIDs: [siteB])]
        )
    }

    func testAnArchivedSiteIsNeverMissing() {
        let lastTuesday = Fixture.date(2026, 10, 13)
        let days = [worked(siteB, lastTuesday, [CrewMember.youID])]
        XCTAssertEqual(evenings(days).first?.siteIDs, [siteB])
        let archived = [Site(id: siteA, name: "A"), Site(id: siteB, name: "B", isArchived: true)]
        XCTAssertEqual(evenings(days, sites: archived), [], "archived last week, still asked about")
        // Work days set on it change nothing.
        XCTAssertEqual(evenings(days, setups: [siteB: SiteSetup(workDays: [3])], sites: archived), [])
    }

    func testTheSitesSwitchAndPauseAreItsOwn() {
        let lastTuesday = Fixture.date(2026, 10, 13)
        let days = [worked(siteA, lastTuesday, [CrewMember.youID]), worked(siteB, lastTuesday, [CrewMember.youID])]
        XCTAssertEqual(evenings(days).first?.siteIDs, [siteA, siteB])
        XCTAssertEqual(evenings(days, setups: [siteA: SiteSetup(eveningReminder: false)]).first?.siteIDs, [siteB])
        XCTAssertEqual(evenings(days, setups: [siteB: SiteSetup(pause: SitePause(start: today))]).first?.siteIDs, [siteA])
    }

    func testOldPreferencesDecodeWithDefaults() throws {
        let json = #"{"isEnabled":true,"weekday":5,"time":{"hour":16,"minute":0},"lookBackDays":10}"#
        let prefs = try JSONDecoder().decode(ReminderPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(prefs.siteRemindersEnabled)
        XCTAssertEqual(prefs.siteReminderTime, TimeOfDay(hour: 18, minute: 0))
        XCTAssertEqual(prefs.weekday, 5)
    }
}
