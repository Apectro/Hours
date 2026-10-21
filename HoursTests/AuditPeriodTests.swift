import XCTest
@testable import Hours

/// The calculation audit, period level: weeks, months and the split by job
/// against the days they are made of.
final class AuditPeriodTests: XCTestCase {
    private let calendar = Fixture.calendar()

    // MARK: - By job

    /// A contract of 37½ hours set as the weekly override, over days that
    /// sum to forty. The month's expected hours follow the override; the
    /// "By job" card on the statistics screen must say the same, or the one
    /// job shows a 2½ hour shortfall every week that the month does not.
    func testAJobsExpectedHoursFollowItsWeeklyOverride() {
        var settings = Fixture.settings()
        var contract = WorkSchedule()
        contract.weeklyTargetOverrideMinutes = 37 * 60 + 30
        settings.setPrimarySchedule(contract)
        settings.addJob(Job(name: "Evenings", schedule: WorkSchedule(minutesByWeekday: [0, 120, 120, 0, 0, 0, 0])))

        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let week = CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 9))
        let days = engine.days(in: week, records: [:], holidays: [])
        let summary = PeriodAggregator.summarize(days, range: week)
        let byJob = engine.jobTotals(for: days)

        let primary = byJob.first { $0.job.isPrimary }
        XCTAssertEqual(primary?.expectedMinutes, 37 * 60 + 30)
        XCTAssertEqual(byJob.map(\.expectedMinutes).reduce(0, +), summary.expectedMinutes)
    }
}
