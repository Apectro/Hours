import XCTest
@testable import Hours

/// Working more than one job.
final class JobTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Eight hours Monday to Friday.
    private var mainJob: Job {
        Job(id: Job.primaryID, name: "Main", tint: .blue, schedule: WorkSchedule(), sortOrder: 0)
    }

    /// Four hours on Tuesdays only.
    private var sideJob: Job {
        Job(
            id: UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!,
            name: "Side",
            tint: .teal,
            schedule: WorkSchedule(minutesByWeekday: [0, 0, 240, 0, 0, 0, 0]),
            sortOrder: 1
        )
    }

    // MARK: - The single-job case is unchanged

    func testWithNoJobsConfiguredThereIsStillExactlyOne() {
        let settings = Fixture.settings()

        XCTAssertEqual(settings.resolvedJobs.count, 1)
        XCTAssertTrue(settings.primaryJob.isPrimary)
        XCTAssertEqual(settings.primaryJob.schedule.weeklyTargetMinutes, 5 * 480)
        XCTAssertFalse(settings.tracksMultipleJobs, "one job means no job pickers anywhere")
    }

    func testASingleJobExpectsExactlyWhatTheScheduleAlwaysDid() {
        let settings = Fixture.settings()
        let result = Fixture.calculator(settings: settings).compute(record: nil, on: Fixture.workingTuesday)

        XCTAssertEqual(result.expectedMinutes, 480)
    }

    // MARK: - Two jobs

    func testExpectedHoursAreSummedAcrossJobs() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]

        let tuesday = Fixture.calculator(settings: settings)
            .compute(record: nil, on: Fixture.workingTuesday)
        XCTAssertEqual(tuesday.expectedMinutes, 480 + 240, "both jobs expect hours on a Tuesday")

        let monday = Fixture.calculator(settings: settings)
            .compute(record: nil, on: Fixture.workingMonday)
        XCTAssertEqual(monday.expectedMinutes, 480, "the side job expects nothing on a Monday")
    }

    func testAnArchivedJobStopsExpectingHours() {
        var settings = Fixture.settings()
        var archived = sideJob
        archived.isArchived = true
        settings.jobs = [mainJob, archived]

        let result = Fixture.calculator(settings: settings)
            .compute(record: nil, on: Fixture.workingTuesday)

        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertFalse(settings.tracksMultipleJobs)
    }

    func testADayWorkedAtBothJobsBalancesToZero() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]

        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(16), jobID: mainJob.id),
                Shift(start: Fixture.time(18), end: Fixture.time(22), jobID: sideJob.id)
            ]
        )
        let result = Fixture.calculator(settings: settings)
            .compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480 + 240)
        XCTAssertEqual(result.expectedMinutes, 480 + 240)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    // MARK: - Splitting a period by job

    func testWorkedTimeIsSplitByTheShiftsJob() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(16), jobID: mainJob.id),
                Shift(start: Fixture.time(18), end: Fixture.time(23), jobID: sideJob.id)
            ]
        )
        let days = engine.days(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: []
        )
        let totals = engine.jobTotals(for: days)

        XCTAssertEqual(totals.count, 2)
        let main = totals.first { $0.job.id == mainJob.id }
        let side = totals.first { $0.job.id == sideJob.id }

        XCTAssertEqual(main?.workedMinutes, 480)
        XCTAssertEqual(main?.expectedMinutes, 480)
        XCTAssertEqual(main?.balanceMinutes, 0)

        XCTAssertEqual(side?.workedMinutes, 300)
        XCTAssertEqual(side?.expectedMinutes, 240)
        XCTAssertEqual(side?.balanceMinutes, 60, "an hour of overtime at the side job only")
    }

    func testAShiftWithNoJobCountsTowardsThePrimaryOne() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        // Recorded before jobs existed, so it carries no job id at all.
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(8), end: Fixture.time(16), jobID: nil)]
        )
        let days = engine.days(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: []
        )
        let totals = engine.jobTotals(for: days)

        XCTAssertEqual(totals.first { $0.job.id == mainJob.id }?.workedMinutes, 480)
        XCTAssertEqual(totals.first { $0.job.id == sideJob.id }?.workedMinutes, 0)
    }

    func testPaidAbsenceCreditsEveryJob() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        let days = engine.days(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: []
        )
        let totals = engine.jobTotals(for: days)

        XCTAssertEqual(totals.first { $0.job.id == mainJob.id }?.creditedMinutes, 480)
        XCTAssertEqual(totals.first { $0.job.id == sideJob.id }?.creditedMinutes, 240)
        XCTAssertTrue(totals.allSatisfy { $0.balanceMinutes == 0 }, "a day of leave moves no balance")
    }

    func testADayOffExpectsNothingFromAnyJob() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .dayOff)
        let days = engine.days(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: []
        )

        XCTAssertTrue(engine.jobTotals(for: days).allSatisfy { $0.expectedMinutes == 0 })
    }

    // MARK: - Resolution never fails

    func testAShiftPointingAtADeletedJobFallsBackToThePrimary() {
        var settings = Fixture.settings()
        settings.jobs = [mainJob]

        let vanished = UUID()
        XCTAssertEqual(settings.job(vanished).id, Job.primaryID)
        XCTAssertEqual(settings.schedule(forJob: vanished).weeklyTargetMinutes, 5 * 480)
    }

    func testJobsSurviveARoundTrip() throws {
        var settings = Fixture.settings()
        settings.jobs = [mainJob, sideJob]

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )

        XCTAssertEqual(restored.jobs.count, 2)
        XCTAssertEqual(restored.job(sideJob.id).name, "Side")
        XCTAssertEqual(restored.job(sideJob.id).schedule.contractedMinutes(forWeekday: 3), 240)
    }

    func testSettingsWrittenBeforeJobsExistedStillLoad() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"appearance":"dark"}"#.utf8)
        )

        XCTAssertTrue(settings.jobs.isEmpty)
        XCTAssertEqual(settings.resolvedJobs.count, 1, "and still resolve to one job")
        XCTAssertTrue(settings.primaryJob.isPrimary)
    }
}
