import XCTest
@testable import Hours

/// What the redesigned widgets are drawn from: the week's bars, a square per
/// working day of the month, the site to show, and the clock's site.
///
/// Everything here is worked out from `DayComputation` values the engine has
/// already resolved, so the widget can only ever agree with the app.
final class WidgetSnapshotBuilderTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let settings = Fixture.settings()

    /// Thursday 6 August 2026. The week runs Monday 3 to Sunday 9.
    private let thursday = Fixture.date(2026, 8, 6)

    private func days(
        in range: CalendarDateRange,
        records: [DayRecord],
        settings: AppSettings? = nil,
        calendar: Calendar? = nil
    ) -> [DayComputation] {
        let engine = Fixture.engine(settings: settings ?? self.settings, calendar: calendar ?? self.calendar)
        return engine.days(
            in: range,
            records: Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first }),
            holidays: []
        )
    }

    /// `CalendarDate.date(in:)` is already midday, well clear of either midnight.
    private func noon(on date: CalendarDate) -> Date {
        date.date(in: calendar)
    }

    // MARK: - The week

    func testTheWeekHasABarForEachDayFromTheFirstWeekday() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        let resolved = days(in: week, records: [
            Fixture.record(on: Fixture.date(2026, 8, 3), start: Fixture.time(7), end: Fixture.time(16)),
            Fixture.record(on: Fixture.date(2026, 8, 5), start: Fixture.time(8), end: Fixture.time(12)),
        ])

        let built = WidgetSnapshotBuilder.week(resolved, today: thursday, calendar: calendar)

        XCTAssertEqual(built.start, Fixture.date(2026, 8, 3), "a Monday-first calendar starts on Monday")
        XCTAssertEqual(built.workedMinutes.count, 7)
        XCTAssertEqual(built.workedMinutes[0], resolved[0].workedMinutes)
        XCTAssertGreaterThan(built.workedMinutes[0], 0)
        XCTAssertEqual(built.workedMinutes[1], 0, "nothing recorded on Tuesday")
        XCTAssertEqual(built.workedMinutes[2], resolved[2].workedMinutes)
    }

    func testASundayFirstCalendarStartsTheWeekOnSunday() {
        let sundayFirst = Fixture.calendar(firstWeekday: 1)
        let week = CalendarDateRange.week(containing: thursday, in: sundayFirst)
        let resolved = days(in: week, records: [], calendar: sundayFirst)

        let built = WidgetSnapshotBuilder.week(resolved, today: thursday, calendar: sundayFirst)

        XCTAssertEqual(built.start, Fixture.date(2026, 8, 2))
        XCTAssertEqual(built.firstWeekday, 1)
    }

    /// The bars add up to what the app's own summary says the week is, so the
    /// big figure above them never disagrees with the bars beneath.
    func testTheWeekTotalIsTheAppsSummaryOfTheWeek() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        let resolved = days(in: week, records: [
            Fixture.record(on: Fixture.date(2026, 8, 3), start: Fixture.time(7), end: Fixture.time(16)),
            Fixture.record(on: Fixture.date(2026, 8, 4), start: Fixture.time(8), end: Fixture.time(16, 30)),
        ])
        let summary = PeriodAggregator.summarize(resolved, range: week, countingThrough: thursday)

        let built = WidgetSnapshotBuilder.week(resolved, today: thursday, calendar: calendar)

        XCTAssertEqual(built.workedMinutes.reduce(0, +), summary.workedMinutes)
    }

    /// "of 40:00" is the whole week's target, not the part of it already past.
    func testTheWeeksTargetIsTheWholeWeek() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        let resolved = days(in: week, records: [])

        let built = WidgetSnapshotBuilder.week(resolved, today: thursday, calendar: calendar)

        XCTAssertEqual(built.expectedMinutes, 5 * 480)
    }

    /// A day left out of totals is left out of the bars, as it is everywhere.
    func testAnExcludedDayAddsNothingToTheWeek() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        var excluded = Fixture.record(on: Fixture.date(2026, 8, 3), start: Fixture.time(7), end: Fixture.time(16))
        excluded.isIncluded = false
        let resolved = days(in: week, records: [excluded])

        let built = WidgetSnapshotBuilder.week(resolved, today: thursday, calendar: calendar)

        XCTAssertEqual(built.workedMinutes[0], 0)
    }

    func testTheRunningClockGrowsTodaysBar() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        let built = WidgetSnapshotBuilder.week(days(in: week, records: []), today: thursday, calendar: calendar)
        let now = noon(on: thursday)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = now
        snapshot.isClockRunning = true
        snapshot.clockStartedAt = now.addingTimeInterval(-90 * 60)
        snapshot.week = built

        let bars = snapshot.weekBars(at: now, calendar: calendar)

        XCTAssertEqual(bars?.count, 7)
        XCTAssertEqual(bars?[3].minutes, 90)
        XCTAssertEqual(bars?[3].isToday, true)
        XCTAssertEqual(bars?.filter(\.isToday).count, 1)
        XCTAssertEqual(snapshot.weekWorked(at: now, calendar: calendar), 90)
    }

    /// Glanced at on Monday morning, last week's bars are not this week's.
    func testLastWeeksBarsAreNotShownAsThisWeeks() {
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.week = WidgetSnapshotBuilder.week(days(in: week, records: []), today: thursday, calendar: calendar)

        let nextMonday = noon(on: Fixture.date(2026, 8, 10))

        XCTAssertNil(snapshot.weekBars(at: nextMonday, calendar: calendar))
        XCTAssertEqual(snapshot.weekWorked(at: nextMonday, calendar: calendar), 0)
        XCTAssertEqual(snapshot.weekExpected(at: nextMonday, calendar: calendar), 0)
    }

    // MARK: - The month's squares

    func testThereIsASquareForEveryWorkingDayAndNoneForTheWeekend() {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let resolved = days(in: august, records: [])

        let marks = WidgetSnapshotBuilder.monthMarks(resolved, today: thursday)

        XCTAssertEqual(marks.count, 21, "August 2026 has 21 weekdays")
        XCTAssertFalse(marks.contains { $0.date == Fixture.saturday })
    }

    /// Leave and holidays are days off: they are neither done nor short.
    func testDaysOffAreLeftOut() {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let resolved = days(in: august, records: [
            Fixture.record(on: Fixture.date(2026, 8, 4), type: .vacation),
            Fixture.record(on: Fixture.date(2026, 8, 5), type: .dayOff),
        ])

        let marks = WidgetSnapshotBuilder.monthMarks(resolved, today: thursday)

        XCTAssertEqual(marks.count, 19)
        XCTAssertFalse(marks.contains { $0.date == Fixture.date(2026, 8, 4) })
    }

    func testEachSquareSaysHowItsDayWent() {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let resolved = days(in: august, records: [
            Fixture.record(on: Fixture.date(2026, 8, 3), start: Fixture.time(7), end: Fixture.time(17)),
            Fixture.record(on: Fixture.date(2026, 8, 4), start: Fixture.time(8), end: Fixture.time(12)),
        ])

        let marks = WidgetSnapshotBuilder.monthMarks(resolved, today: thursday)
        let state = { (day: Int) in marks.first { $0.date == Fixture.date(2026, 8, day) }?.state }

        XCTAssertEqual(state(3), .done)
        XCTAssertEqual(state(4), .short)
        XCTAssertEqual(state(5), .short, "a past working day with nothing recorded is short")
        XCTAssertEqual(state(6), .today)
        XCTAssertEqual(state(7), .toCome)
    }

    /// After midnight the square that was today takes the day's own figures,
    /// and the new day becomes today, without waiting for the app.
    func testTheSquaresMoveOnAtMidnight() {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let resolved = days(in: august, records: [])
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.todayWorkedMinutes = 480
        snapshot.todayExpectedMinutes = 480
        snapshot.monthMarks = WidgetSnapshotBuilder.monthMarks(resolved, today: thursday)

        let friday = noon(on: Fixture.date(2026, 8, 7))
        let marks = snapshot.monthMarks(at: friday, calendar: calendar)
        let state = { (day: Int) in marks.first { $0.date == Fixture.date(2026, 8, day) }?.state }

        XCTAssertEqual(state(6), .done)
        XCTAssertEqual(state(7), .today)
        XCTAssertEqual(state(10), .toCome)
    }

    func testLastMonthsSquaresAreNotShown() {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.monthMarks = WidgetSnapshotBuilder.monthMarks(days(in: august, records: []), today: thursday)

        XCTAssertTrue(snapshot.monthMarks(at: noon(on: Fixture.date(2026, 9, 1)), calendar: calendar).isEmpty)
    }

    // MARK: - Which site

    private func siteDay(_ site: Site, _ day: Int, present: [UUID] = [CrewMember.youID]) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, day),
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present.map { Attendance(memberID: $0) }
        )
    }

    func testTheSiteShownIsTheOneWorkedMostRecently() {
        let north = Site(name: "North", sortOrder: 0)
        let south = Site(name: "South", sortOrder: 1)

        let chosen = WidgetSnapshotBuilder.mostRecentSite(
            among: [north, south],
            recentDays: [siteDay(north, 3), siteDay(south, 5), siteDay(north, 4)],
            today: thursday
        )

        XCTAssertEqual(chosen?.id, south.id)
    }

    /// A day written up for the crew while you were elsewhere is not one you
    /// worked there.
    func testADayYouWereNotOnDoesNotCount() {
        let north = Site(name: "North", sortOrder: 0)
        let south = Site(name: "South", sortOrder: 1)

        let chosen = WidgetSnapshotBuilder.mostRecentSite(
            among: [north, south],
            recentDays: [siteDay(north, 4), siteDay(south, 5, present: [UUID()])],
            today: thursday
        )

        XCTAssertEqual(chosen?.id, north.id)
    }

    func testAnArchivedSiteIsNeverShown() {
        let current = Site(name: "Current", sortOrder: 0)
        let finished = Site(name: "Finished", isArchived: true, sortOrder: 1)

        let chosen = WidgetSnapshotBuilder.mostRecentSite(
            among: [current, finished],
            recentDays: [siteDay(finished, 5), siteDay(current, 3)],
            today: thursday
        )

        XCTAssertEqual(chosen?.id, current.id)
    }

    /// A day entered in advance is not one already worked.
    func testADayInTheFutureDoesNotCount() {
        let north = Site(name: "North", sortOrder: 0)
        let south = Site(name: "South", sortOrder: 1)

        let chosen = WidgetSnapshotBuilder.mostRecentSite(
            among: [north, south],
            recentDays: [siteDay(north, 4), siteDay(south, 10)],
            today: thursday
        )

        XCTAssertEqual(chosen?.id, north.id)
    }

    func testWithNothingWorkedYetTheFirstActiveSiteIsShown() {
        let second = Site(name: "Second", sortOrder: 1)
        let first = Site(name: "First", sortOrder: 0)

        let chosen = WidgetSnapshotBuilder.mostRecentSite(among: [second, first], recentDays: [], today: thursday)

        XCTAssertEqual(chosen?.id, first.id)
    }

    func testNoActiveSiteMeansNoSite() {
        let finished = Site(name: "Finished", isArchived: true)

        XCTAssertNil(WidgetSnapshotBuilder.mostRecentSite(among: [], recentDays: [], today: thursday))
        XCTAssertNil(WidgetSnapshotBuilder.mostRecentSite(
            among: [finished],
            recentDays: [siteDay(finished, 5)],
            today: thursday
        ))
    }

    // MARK: - The site's card

    func testTheSiteCardDescribesItsLastWrittenDay() {
        let site = Site(name: "Trg Pravde")
        let ivan = CrewMember(siteID: site.id, name: "Ivan Horvat", sortOrder: 0)
        let dario = CrewMember(siteID: site.id, name: "Dario Babić", sortOrder: 1)
        let last = siteDay(site, 5, present: [CrewMember.youID, ivan.id, dario.id])

        let card = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: last, crew: [ivan, dario])

        XCTAssertEqual(card.id, site.id)
        XCTAssertEqual(card.name, "Trg Pravde")
        XCTAssertFalse(card.isTodayWritten)
        XCTAssertEqual(card.lastDay, Fixture.date(2026, 8, 5))
        XCTAssertEqual(card.lastDayPeople, 3)
        XCTAssertTrue(card.includesYou)
        XCTAssertEqual(card.initials, ["IH", "DB"])
        XCTAssertEqual(card.lastStart, Fixture.time(7))
        XCTAssertEqual(card.lastEnd, Fixture.time(16))
        XCTAssertEqual(card.morePeople, 0)
    }

    func testTodayWrittenIsSaidSo() {
        let site = Site(name: "Trg Pravde")

        let card = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: siteDay(site, 6), crew: [])

        XCTAssertTrue(card.isTodayWritten)
    }

    /// Four faces fit; the rest are a count.
    func testAtMostFourFacesAndTheRestCounted() {
        let site = Site(name: "Big")
        let crew = (0..<6).map { CrewMember(siteID: site.id, name: "Person \($0)", sortOrder: $0) }
        let last = siteDay(site, 5, present: [CrewMember.youID] + crew.map(\.id))

        let card = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: last, crew: crew)

        XCTAssertEqual(card.lastDayPeople, 7)
        XCTAssertTrue(card.includesYou)
        XCTAssertEqual(card.initials.count, 3, "you take the fourth place")
        XCTAssertEqual(card.morePeople, 3)
    }

    func testANewSiteHasNoLastDay() {
        let site = Site(name: "New")

        let card = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: nil, crew: [])

        XCTAssertNil(card.lastDay)
        XCTAssertEqual(card.lastDayPeople, 0)
        XCTAssertFalse(card.includesYou)
        XCTAssertTrue(card.initials.isEmpty)
    }

    func testInitials() {
        XCTAssertEqual(WidgetSnapshotBuilder.initials(of: "Ivan Horvat"), "IH")
        XCTAssertEqual(WidgetSnapshotBuilder.initials(of: "Ana Marija Kovač"), "AK")
        XCTAssertEqual(WidgetSnapshotBuilder.initials(of: "dario"), "D")
        XCTAssertEqual(WidgetSnapshotBuilder.initials(of: "  "), "?")
        XCTAssertEqual(WidgetSnapshotBuilder.initials(of: "Željko Šimić"), "ŽŠ")
    }

    /// Yesterday's "written" must not read as today's after midnight.
    func testTodayWrittenDoesNotCarryIntoTheNextDay() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        let site = Site(name: "Trg Pravde")
        snapshot.site = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: siteDay(site, 6), crew: [])

        XCTAssertTrue(snapshot.isSiteTodayWritten(at: noon(on: thursday), calendar: calendar))
        XCTAssertFalse(snapshot.isSiteTodayWritten(at: noon(on: Fixture.date(2026, 8, 7)), calendar: calendar))
    }

    // MARK: - The clock's site

    func testTheClocksSiteIsTheOneSiteOnItsJob() {
        let job = UUID()
        let running = RunningShift(date: thursday, start: Fixture.time(7), startedAt: noon(on: thursday), jobID: job)
        let sites = [Site(name: "Elsewhere", jobID: UUID()), Site(name: "Trg Pravde", jobID: job)]

        XCTAssertEqual(WidgetSnapshotBuilder.clockSiteName(for: running, among: sites), "Trg Pravde")
    }

    /// Two sites on the same job, or a clock with no job, would be a guess.
    func testNoSiteIsNamedWhenItWouldBeAGuess() {
        let job = UUID()
        let onJob = RunningShift(date: thursday, start: Fixture.time(7), startedAt: noon(on: thursday), jobID: job)
        let noJob = RunningShift(date: thursday, start: Fixture.time(7), startedAt: noon(on: thursday))

        XCTAssertNil(WidgetSnapshotBuilder.clockSiteName(
            for: onJob,
            among: [Site(name: "A", jobID: job), Site(name: "B", jobID: job)]
        ))
        XCTAssertNil(WidgetSnapshotBuilder.clockSiteName(for: noJob, among: [Site(name: "A")]))
        XCTAssertNil(WidgetSnapshotBuilder.clockSiteName(
            for: onJob,
            among: [Site(name: "Old", jobID: job, isArchived: true)]
        ))
        XCTAssertNil(WidgetSnapshotBuilder.clockSiteName(for: nil, among: [Site(name: "A", jobID: job)]))
    }

    // MARK: - Off at

    func testAWorkingDayEndsAtTheSchedulesDefaultEnd() {
        let today = days(in: CalendarDateRange(single: thursday), records: []).first

        XCTAssertEqual(
            WidgetSnapshotBuilder.defaultEnd(today: today, running: nil, settings: settings),
            Fixture.time(16, 30)
        )
    }

    func testADayOffHasNoEnd() {
        let saturday = days(in: CalendarDateRange(single: Fixture.saturday), records: []).first

        XCTAssertNil(WidgetSnapshotBuilder.defaultEnd(today: saturday, running: nil, settings: settings))
    }

    func testOffAtIsNotCarriedIntoTheNextDay() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.todayDefaultEnd = Fixture.time(16)

        XCTAssertEqual(snapshot.defaultEnd(at: noon(on: thursday), calendar: calendar), Fixture.time(16))
        XCTAssertNil(snapshot.defaultEnd(at: noon(on: Fixture.date(2026, 8, 7)), calendar: calendar))
    }

    // MARK: - Files written by another version

    /// The file the previous version wrote, field for field. A widget updated
    /// before the app has run once reads exactly this.
    func testTheFileThePreviousVersionWroteStillDecodes() throws {
        let json = Data("""
        {"generatedAt": 0, "isClockRunning": true, "clockStartedAt": 0, "clockJobName": "Site work",
         "todayWorkedMinutes": 90, "todayExpectedMinutes": 480, "monthWorkedMinutes": 600,
         "monthExpectedMinutes": 960, "monthBalanceMinutes": -360, "showsBalance": true,
         "unrecordedDayCount": 2, "durationStyle": "hoursAndMinutes", "isUnlocked": true}
        """.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.todayWorkedMinutes, 90)
        XCTAssertEqual(decoded.clockJobName, "Site work")
        XCTAssertTrue(decoded.isUnlocked)
        XCTAssertNil(decoded.week)
        XCTAssertTrue(decoded.monthMarks.isEmpty)
        XCTAssertNil(decoded.clockSiteName)
        XCTAssertNil(decoded.todayDefaultEnd)
        XCTAssertNil(decoded.site)
    }

    func testTheNewFiguresSurviveARoundTrip() throws {
        let august = YearMonth(year: 2026, month: 8).range(in: calendar)
        let week = CalendarDateRange.week(containing: thursday, in: calendar)
        let site = Site(name: "Trg Pravde")
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.week = WidgetSnapshotBuilder.week(days(in: week, records: []), today: thursday, calendar: calendar)
        snapshot.monthMarks = WidgetSnapshotBuilder.monthMarks(days(in: august, records: []), today: thursday)
        snapshot.clockSiteName = "Trg Pravde"
        snapshot.todayDefaultEnd = Fixture.time(16)
        snapshot.site = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: siteDay(site, 5), crew: [])

        let data = try JSONEncoder().encode(snapshot)

        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
    }

    /// A damaged site block loses the site card, not the whole widget.
    func testAnUnreadableSiteLosesOnlyTheSite() throws {
        let json = Data(#"{"todayWorkedMinutes": 90, "site": {"name": 12}}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.todayWorkedMinutes, 90)
        XCTAssertNil(decoded.site)
    }
}
