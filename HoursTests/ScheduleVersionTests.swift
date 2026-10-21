import XCTest
@testable import Hours

/// Schedules that change from a date onward.
///
/// A new contract from November must not rewrite October: October was
/// worked, and possibly handed in, under the old one. Every figure read for a
/// date reads the version of the schedule in force on that date.
final class ScheduleVersionTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Monday to Friday, 8 h: 40 h a week.
    private let fullWeek = WorkSchedule()
    /// Monday to Thursday, 8 h: 32 h a week, Fridays off.
    private let fourDays = WorkSchedule(minutesByWeekday: [0, 480, 480, 480, 480, 0, 0])
    /// Monday to Friday, 4 h.
    private let halfDays = WorkSchedule(minutesByWeekday: [0, 240, 240, 240, 240, 240, 0])

    /// Monday 2 November 2026.
    private let november2 = Fixture.date(2026, 11, 2)

    private func expected(_ settings: AppSettings, on date: CalendarDate) -> Int {
        Fixture.calculator(settings: settings, calendar: calendar).compute(record: nil, on: date).expectedMinutes
    }

    private func expected(_ settings: AppSettings, over range: CalendarDateRange) -> Int {
        Fixture.engine(settings: settings, calendar: calendar)
            .summary(in: range, records: [:], holidays: [])
            .expectedMinutes
    }

    private func primaryChanging(to schedule: WorkSchedule, from date: CalendarDate?) -> AppSettings {
        var settings = Fixture.settings(schedule: fullWeek)
        settings.changePrimarySchedule(to: schedule, from: date)
        return settings
    }

    // MARK: - The version in force

    func testTheVersionInForceIsTheLatestThatHasStarted() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)

        XCTAssertEqual(history.schedule(on: Fixture.date(2026, 10, 30)), fullWeek)
        XCTAssertEqual(history.schedule(on: november2), fourDays, "a change applies from its own day")
        XCTAssertEqual(history.schedule(on: Fixture.date(2027, 3, 1)), fourDays)
    }

    func testExpectedHoursFollowTheScheduleInForceOnTheDay() {
        let settings = primaryChanging(to: fourDays, from: november2)

        let fridayBefore = Fixture.calculator(settings: settings, calendar: calendar)
            .compute(record: nil, on: Fixture.date(2026, 10, 30))
        let fridayAfter = Fixture.calculator(settings: settings, calendar: calendar)
            .compute(record: nil, on: Fixture.date(2026, 11, 6))

        XCTAssertEqual(fridayBefore.expectedMinutes, 480)
        XCTAssertEqual(fridayBefore.dayType.id, .work)
        XCTAssertEqual(fridayAfter.expectedMinutes, 0)
        XCTAssertEqual(fridayAfter.dayType.id, .weekend, "a Friday off under the new contract")
    }

    func testAChangeMidMonthSplitsTheMonth() {
        // From Monday 16 November. 2 to 13 November: ten weekdays at 8 h.
        // 16 to 30 November: nine Monday-to-Thursdays at 8 h.
        let settings = primaryChanging(to: fourDays, from: Fixture.date(2026, 11, 16))
        let november = YearMonth(year: 2026, month: 11).range(in: calendar)

        XCTAssertEqual(expected(settings, over: november), (10 + 9) * 480)
    }

    func testAChangeMidWeekSplitsTheWeek() {
        // From Wednesday 4 November: Monday and Tuesday at 8 h, the rest at 4 h.
        let settings = primaryChanging(to: halfDays, from: Fixture.date(2026, 11, 4))
        let week = CalendarDateRange.week(containing: november2, in: calendar)

        XCTAssertEqual(expected(settings, over: week), 2 * 480 + 3 * 240)
    }

    func testEachVersionKeepsItsOwnWeeklyOverride() {
        var contracted = fullWeek
        contracted.weeklyTargetOverrideMinutes = 37 * 60 + 30
        var settings = Fixture.settings(schedule: contracted)
        settings.changePrimarySchedule(to: fullWeek, from: november2)

        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 10, 26)), 450, "37½ h spread over five days")
        XCTAssertEqual(expected(settings, on: november2), 480, "the new contract has no override")
    }

    // MARK: - Jobs

    private let sideID = UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!

    /// Main: 40 h, then Monday to Thursday from 2 November. Side: Tuesdays
    /// 4 h, then Tuesdays and Thursdays from 16 November.
    private func twoJobs(sideArchived: Bool = false) -> AppSettings {
        var main = Job(id: Job.primaryID, name: "Main", schedule: fullWeek, sortOrder: 0)
        main.schedules.change(to: fourDays, from: november2)
        var side = Job(
            id: sideID,
            name: "Side",
            schedule: WorkSchedule(minutesByWeekday: [0, 0, 240, 0, 0, 0, 0]),
            isArchived: sideArchived,
            sortOrder: 1
        )
        side.schedules.change(to: WorkSchedule(minutesByWeekday: [0, 0, 240, 0, 240, 0, 0]), from: Fixture.date(2026, 11, 16))
        var settings = Fixture.settings()
        settings.jobs = [main, side]
        return settings
    }

    func testEachJobKeepsItsOwnVersions() {
        let settings = twoJobs()

        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 11, 5)), 480, "Thursday before the side job's change")
        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 11, 19)), 480 + 240, "Thursday after it")
        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 10, 30)), 480, "Friday before the main job's change")
        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 11, 6)), 0)
    }

    func testJobTotalsReadEachJobsVersionForTheDay() {
        let settings = twoJobs()
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        // Monday 26 October to Sunday 8 November: a week either side of the
        // main job's change.
        let range = CalendarDateRange(start: Fixture.date(2026, 10, 26), end: Fixture.date(2026, 11, 8))
        let days = engine.days(in: range, records: [:], holidays: [])

        let totals = Dictionary(uniqueKeysWithValues: engine.jobTotals(for: days).map { ($0.job.id, $0.expectedMinutes) })

        XCTAssertEqual(totals[Job.primaryID], 5 * 480 + 4 * 480)
        XCTAssertEqual(totals[sideID], 2 * 240)
    }

    func testAnArchivedJobsVersionsExpectNothing() {
        let settings = twoJobs(sideArchived: true)

        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 11, 19)), 480)
    }

    // MARK: - Stored settings

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testSettingsWrittenBeforeVersionsReadAsOneVersionSinceAlways() throws {
        let settings = try decode("""
        {"schedule": {"minutesByWeekday": [0, 480, 480, 480, 480, 0, 0]},
         "jobs": [
           {"id": "00000000-0000-4000-8000-000000000001", "name": "Main",
            "schedule": {"minutesByWeekday": [0, 480, 480, 480, 480, 0, 0]}},
           {"id": "00000000-0000-4000-8000-0000000000AA", "name": "Side",
            "schedule": {"minutesByWeekday": [0, 0, 240, 0, 0, 0, 0]}}
         ]}
        """)

        XCTAssertEqual(settings.schedules.versions.map(\.from), [nil])
        XCTAssertEqual(settings.job(sideID).schedules.versions.map(\.from), [nil])
        XCTAssertEqual(expected(settings, on: Fixture.date(2020, 1, 7)), 480 + 240, "a Tuesday years ago")
        XCTAssertEqual(expected(settings, on: Fixture.date(2026, 11, 6)), 0, "every Friday off, as before")
    }

    func testVersionsSurviveARoundTrip() throws {
        var settings = twoJobs()
        settings.jobs = []
        settings.changePrimarySchedule(to: fourDays, from: november2)
        let withJobs = twoJobs()

        for original in [settings, withJobs] {
            let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
            XCTAssertEqual(restored, original)
        }
    }

    /// An older version of the app knows only `schedule`. It reads the newest
    /// version there: that applies the new contract to all of history, which
    /// is what it always did, rather than the old contract to the future.
    func testTheNewestVersionIsWrittenWhereAnOlderAppLooks() throws {
        let settings = twoJobs()

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        let jobs = json?["jobs"] as? [[String: Any]]
        let main = jobs?.first { $0["id"] as? String == Job.primaryID.uuidString }
        let schedule = try JSONSerialization.data(withJSONObject: main?["schedule"] as Any)

        XCTAssertEqual(try JSONDecoder().decode(WorkSchedule.self, from: schedule), fourDays)
    }

    /// The same blob, synced back from a device on an older version after it
    /// edited `schedule`: the edit lands on the newest version and the
    /// earlier ones are kept.
    func testAnEditFromAnOlderAppReachesTheNewestVersion() throws {
        let settings = try decode("""
        {"schedule": {"minutesByWeekday": [0, 240, 240, 240, 240, 240, 0]},
         "scheduleVersions": [
           {"schedule": {"minutesByWeekday": [0, 480, 480, 480, 480, 480, 0]}},
           {"from": 20261102, "schedule": {"minutesByWeekday": [0, 480, 480, 480, 480, 0, 0]}}
         ]}
        """)

        XCTAssertEqual(settings.schedules.schedule(on: Fixture.date(2026, 10, 30)), fullWeek)
        XCTAssertEqual(settings.schedules.schedule(on: Fixture.date(2026, 11, 3)), halfDays)
    }

    // MARK: - The balance

    func testTheRunningBalanceCrossesAChange() {
        // 8 h every weekday from Monday 26 October to Friday 6 November, and
        // Fridays off from 2 November: the last Friday is 8 h over.
        var records: [Int: DayRecord] = [:]
        for date in CalendarDateRange(start: Fixture.date(2026, 10, 26), end: Fixture.date(2026, 11, 6)).days(in: calendar)
        where (2...6).contains(date.weekday(in: calendar)) {
            records[date.key] = DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(16))
        }
        let settings = primaryChanging(to: fourDays, from: november2)
        let engine = Fixture.engine(settings: settings, calendar: calendar, firstRecorded: Fixture.date(2026, 10, 26))

        let balance = engine.runningBalance(
            through: Fixture.date(2026, 11, 6),
            holidays: [],
            countingThrough: Fixture.date(2026, 11, 6),
            records: { range in records.filter { range.dayKeys.contains($0.key) } }
        )

        XCTAssertEqual(balance, 480)
    }

    func testASiteDayCountsAgainstTheVersionOnItsDate() {
        let settings = primaryChanging(to: fourDays, from: november2)
        let site = UUID()
        func onSite(_ date: CalendarDate) -> DayRecord {
            DayRecord(date: date, shifts: [Shift(start: Fixture.time(8), end: Fixture.time(16), siteID: site)])
        }
        let calculator = Fixture.calculator(settings: settings, calendar: calendar)

        XCTAssertEqual(calculator.compute(record: onSite(Fixture.date(2026, 10, 30)), on: Fixture.date(2026, 10, 30)).balanceMinutes, 0)
        XCTAssertEqual(calculator.compute(record: onSite(Fixture.date(2026, 11, 6)), on: Fixture.date(2026, 11, 6)).balanceMinutes, 480)
    }

    // MARK: - Changing the history

    func testAChangeFromADateReplacesEverythingAfterIt() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)
        history.change(to: halfDays, from: Fixture.date(2026, 12, 7))

        history.change(to: halfDays, from: Fixture.date(2026, 11, 16))

        XCTAssertEqual(history.versions.map(\.from), [nil, november2, Fixture.date(2026, 11, 16)])
        XCTAssertEqual(history.schedule(on: Fixture.date(2026, 12, 10)), halfDays)
    }

    func testAChangeOnTheSameDayReplacesThatVersion() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)
        history.change(to: halfDays, from: november2)

        XCTAssertEqual(history.versions.count, 2)
        XCTAssertEqual(history.schedule(on: november2), halfDays)
    }

    func testItWasAlwaysLikeThisRewritesHistory() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)

        history.change(to: halfDays, from: nil)

        XCTAssertEqual(history.versions, [ScheduleVersion(from: nil, schedule: halfDays)])
    }

    func testRemovingAChangeLetsTheVersionBeforeItRunOn() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)
        history.change(to: halfDays, from: Fixture.date(2026, 12, 7))

        history.removeChange(from: november2)

        XCTAssertEqual(history.schedule(on: Fixture.date(2026, 11, 6)), fullWeek)
        XCTAssertEqual(history.schedule(on: Fixture.date(2026, 12, 7)), halfDays)
    }

    func testRemovingAChangeThatIsNotThereChangesNothing() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)

        history.removeChange(from: Fixture.date(2026, 1, 1))

        XCTAssertEqual(history.versions.map(\.from), [nil, november2], "nothing starts on 1 January")
    }

    func testTheVersionInForceTodayIsWhatTheEditorStartsFrom() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: Fixture.date(2026, 12, 1))

        XCTAssertEqual(history.schedule(on: Fixture.date(2026, 11, 20)), fullWeek, "a change still to come is not today's")
        XCTAssertEqual(history.latest, fourDays)
    }

    func testClosedMonthsAChangeWouldRewriteAreNamed() {
        var history = ScheduleHistory(fullWeek)
        history.change(to: fourDays, from: november2)
        let lock = MonthLock(months: [YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)])

        XCTAssertEqual(history.closedMonths(affectedByChangeFrom: Fixture.date(2026, 11, 16), lock: lock), [])
        XCTAssertEqual(
            history.closedMonths(affectedByChangeFrom: Fixture.date(2026, 10, 15), lock: lock),
            [YearMonth(year: 2026, month: 10)],
            "October is closed and its second half would change"
        )
        XCTAssertEqual(
            history.closedMonths(affectedByChangeFrom: nil, lock: lock),
            [YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)]
        )
    }

    // MARK: - Pre-fill

    func testANewDayIsPrefilledFromItsOwnVersion() {
        var later = fullWeek
        later.defaultStart = Fixture.time(7)
        later.defaultEnd = Fixture.time(15, 30)
        let settings = primaryChanging(to: later, from: november2)
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        XCTAssertEqual(engine.draftRecord(for: Fixture.date(2026, 10, 30), holidays: []).shifts.first?.start, Fixture.time(8))
        XCTAssertEqual(engine.draftRecord(for: Fixture.date(2026, 11, 3), holidays: []).shifts.first?.start, Fixture.time(7))
    }

    func testFillingAFortnightUsesEachDaysVersion() {
        var later = fourDays
        later.defaultStart = Fixture.time(7)
        let settings = primaryChanging(to: later, from: november2)
        let request = BulkEditRequest(
            range: CalendarDateRange(start: Fixture.date(2026, 10, 26), end: Fixture.date(2026, 11, 8)),
            action: .applyWorkingPattern
        )

        let plan = BulkEditor.plan(request, existing: [:], settings: settings, calendar: calendar)
        let starts = Dictionary(uniqueKeysWithValues: plan.changes.map { ($0.date, $0.shifts.first?.start) })

        XCTAssertEqual(plan.changes.count, 5 + 4, "Friday 6 November is not a working day any more")
        XCTAssertEqual(starts[Fixture.date(2026, 10, 30)], Fixture.time(8))
        XCTAssertEqual(starts[Fixture.date(2026, 11, 2)], Fixture.time(7))
    }

    func testTheWidgetsEndOfDayIsTodaysVersion() {
        var later = fullWeek
        later.defaultEnd = Fixture.time(15)
        let settings = primaryChanging(to: later, from: november2)
        let calculator = Fixture.calculator(settings: settings, calendar: calendar)

        let before = calculator.compute(record: nil, on: Fixture.date(2026, 10, 30))
        let after = calculator.compute(record: nil, on: Fixture.date(2026, 11, 3))

        XCTAssertEqual(WidgetSnapshotBuilder.defaultEnd(today: before, running: nil, settings: settings), Fixture.time(16, 30))
        XCTAssertEqual(WidgetSnapshotBuilder.defaultEnd(today: after, running: nil, settings: settings), Fixture.time(15))
    }
}
