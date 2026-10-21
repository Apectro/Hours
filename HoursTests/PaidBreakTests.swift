import XCTest
@testable import Hours

/// A job whose employer pays for breaks.
///
/// The break is still recorded and still reported; only the worked figure
/// stops subtracting it. Every test here is the same 07:00–16:00 day with a
/// 30-minute break, which comes to 8:30 when the break is unpaid and to 9:00
/// when it is paid.
final class PaidBreakTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func job(_ suffix: String, name: String, paid: Bool, archived: Bool = false, sortOrder: Int) -> Job {
        Job(
            id: UUID(uuidString: "00000000-0000-4000-8000-0000000000\(suffix)")!,
            name: name,
            tint: .teal,
            schedule: WorkSchedule(),
            breaksArePaid: paid,
            isArchived: archived,
            sortOrder: sortOrder
        )
    }

    private func mainJob(paid: Bool) -> Job {
        Job(id: Job.primaryID, name: "Main", tint: .blue, schedule: WorkSchedule(), breaksArePaid: paid, sortOrder: 0)
    }

    private func shift(_ start: Int, _ end: Int, breakMinutes: Int = 30, job: UUID?) -> Shift {
        Shift(start: Fixture.time(start), end: Fixture.time(end), breaks: [.duration(breakMinutes)], jobID: job)
    }

    private func compute(_ shifts: [Shift], settings: AppSettings) -> DayComputation {
        Fixture.calculator(settings: settings)
            .compute(record: DayRecord(date: Fixture.workingTuesday, shifts: shifts), on: Fixture.workingTuesday)
    }

    // MARK: - Worked time

    func testAPaidBreakCountsAsWorked() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: true), job("AA", name: "Side", paid: false, sortOrder: 1)]

        let result = compute([shift(7, 16, job: Job.primaryID)], settings: settings)

        XCTAssertEqual(result.workedMinutes, 540)
        XCTAssertEqual(result.breakMinutes, 30, "the break is still written down")
        XCTAssertEqual(result.shifts.first?.workedMinutes, 540)
        XCTAssertEqual(result.shifts.first?.breakMinutes, 30)
    }

    func testAnUnpaidBreakIsStillSubtracted() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: false), job("AA", name: "Side", paid: true, sortOrder: 1)]

        let result = compute([shift(7, 16, job: Job.primaryID)], settings: settings)

        XCTAssertEqual(result.workedMinutes, 510)
        XCTAssertEqual(result.breakMinutes, 30)
    }

    func testEachShiftFollowsItsOwnJob() {
        var settings = Fixture.settings()
        let side = job("AA", name: "Side", paid: true, sortOrder: 1)
        settings.jobs = [mainJob(paid: false), side]

        // A morning at the main job and an evening at the side job, a
        // half-hour break at each.
        let result = compute(
            [shift(7, 12, job: Job.primaryID), shift(13, 18, job: side.id)],
            settings: settings
        )

        XCTAssertEqual(result.workedMinutes, 270 + 300)
        XCTAssertEqual(result.breakMinutes, 60)
        XCTAssertEqual(result.shifts.map(\.workedMinutes), [270, 300])

        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [shift(7, 12, job: Job.primaryID), shift(13, 18, job: side.id)]
        )
        let days = engine.days(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: []
        )
        let totals = engine.jobTotals(for: days)
        XCTAssertEqual(totals.first { $0.job.id == Job.primaryID }?.workedMinutes, 270)
        XCTAssertEqual(totals.first { $0.job.id == side.id }?.workedMinutes, 300)
    }

    func testTheBalanceFollowsTheWorkedTime() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: true), job("AA", name: "Side", paid: false, sortOrder: 1)]
        // Only the main job expects hours, so the day's target is its eight.
        settings.jobs[1].schedule = WorkSchedule(minutesByWeekday: [0, 0, 0, 0, 0, 0, 0])

        let result = compute([shift(7, 16, job: Job.primaryID)], settings: settings)

        XCTAssertEqual(result.expectedMinutes, 480, "expected hours come from the contract, not the shift")
        XCTAssertEqual(result.balanceMinutes, 60)
    }

    func testABreakLongerThanTheShiftStillWarns() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: true), job("AA", name: "Side", paid: false, sortOrder: 1)]

        let result = compute([shift(7, 8, breakMinutes: 90, job: Job.primaryID)], settings: settings)

        XCTAssertTrue(result.warnings.contains(.breakLongerThanShift))
    }

    // MARK: - Which job decides

    func testAShiftWithNoJobFollowsThePrimaryJob() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: true), job("AA", name: "Side", paid: false, sortOrder: 1)]

        XCTAssertEqual(compute([shift(7, 16, job: nil)], settings: settings).workedMinutes, 540)
    }

    func testTheSingleJobCaseKeepsTheRuleWithoutAJobList() {
        var settings = Fixture.settings()
        settings.setPrimaryBreaksArePaid(true)

        XCTAssertTrue(settings.jobs.isEmpty, "one job stays the single-job case")
        XCTAssertTrue(settings.primaryJob.breaksArePaid)
        XCTAssertEqual(compute([shift(7, 16, job: nil)], settings: settings).workedMinutes, 540)
    }

    func testTheRuleSurvivesAddingAndRemovingASecondJob() {
        var settings = Fixture.settings()
        settings.setPrimaryBreaksArePaid(true)

        let side = job("AA", name: "Side", paid: false, sortOrder: 1)
        settings.addJob(side)
        XCTAssertTrue(settings.job(Job.primaryID).breaksArePaid, "materialising the primary job keeps it")
        XCTAssertFalse(settings.job(side.id).breaksArePaid)

        settings.removeJob(id: side.id)
        XCTAssertTrue(settings.jobs.isEmpty)
        XCTAssertTrue(settings.primaryJob.breaksArePaid, "collapsing back to one job keeps it")
    }

    func testSettingThePrimaryRuleWithSeveralJobsWritesToTheJob() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: false), job("AA", name: "Side", paid: false, sortOrder: 1)]

        settings.setPrimaryBreaksArePaid(true)

        XCTAssertTrue(settings.job(Job.primaryID).breaksArePaid)
        XCTAssertFalse(settings.job(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!).breaksArePaid)
    }

    func testAnArchivedJobKeepsItsRuleForItsHistory() {
        var settings = Fixture.settings()
        let old = job("BB", name: "Old", paid: true, archived: true, sortOrder: 1)
        settings.jobs = [mainJob(paid: false), old]

        XCTAssertEqual(compute([shift(7, 16, job: old.id)], settings: settings).workedMinutes, 540)
    }

    func testAShiftPointingAtADeletedJobFollowsThePrimary() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: true), job("AA", name: "Side", paid: false, sortOrder: 1)]

        XCTAssertEqual(compute([shift(7, 16, job: UUID())], settings: settings).workedMinutes, 540)
    }

    // MARK: - The default day

    func testTheDefaultDayCountsThePaidBreak() {
        // 08:00–16:30 with a 30-minute break.
        let schedule = WorkSchedule()

        XCTAssertEqual(schedule.defaultShiftMinutes(breaksArePaid: false), 480)
        XCTAssertEqual(schedule.defaultShiftMinutes(breaksArePaid: true), 510)
    }

    // MARK: - Stored settings

    func testAJobWrittenBeforeTheSwitchExistedDoesNotPayBreaks() throws {
        let decoded = try JSONDecoder().decode(
            Job.self,
            from: Data(#"{"id":"00000000-0000-4000-8000-0000000000AA","name":"Side","sortOrder":1}"#.utf8)
        )

        XCTAssertFalse(decoded.breaksArePaid)
        XCTAssertEqual(decoded.name, "Side")
    }

    func testTheSwitchSurvivesARoundTrip() throws {
        var settings = Fixture.settings()
        settings.jobs = [mainJob(paid: false), job("AA", name: "Side", paid: true, sortOrder: 1)]

        let restored = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertFalse(restored.job(Job.primaryID).breaksArePaid)
        XCTAssertTrue(restored.job(UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!).breaksArePaid)
    }

    func testTheSingleJobSwitchSurvivesARoundTrip() throws {
        var settings = Fixture.settings()
        settings.setPrimaryBreaksArePaid(true)

        let restored = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(settings))

        XCTAssertTrue(restored.primaryJob.breaksArePaid)
    }

    func testSettingsWrittenBeforeTheSwitchExistedDoNotPayBreaks() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))

        XCTAssertFalse(settings.primaryJob.breaksArePaid)
    }
}
