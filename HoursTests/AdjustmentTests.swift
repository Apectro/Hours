import XCTest
@testable import Hours

/// Overtime leaving the balance for a reason.
final class AdjustmentTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func day(_ date: CalendarDate, minutes: Int, reason: AdjustmentReason) -> DayRecord {
        DayRecord(
            date: date,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)],
            adjustmentMinutes: minutes,
            adjustmentReason: reason
        )
    }

    func testAPayoutTakesHoursOutOfTheBalanceWithoutTouchingTheHoursWorked() {
        let record = day(Fixture.workingTuesday, minutes: -600, reason: .payout)
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480, "the day was still a full day's work")
        XCTAssertEqual(result.balanceMinutes, -600)
        XCTAssertEqual(result.adjustmentReason, .payout)
    }

    func testAdjustmentsAreTotalledByReason() {
        let engine = Fixture.engine(calendar: calendar)
        let records: [Int: DayRecord] = [
            Fixture.workingMonday.key: day(Fixture.workingMonday, minutes: -600, reason: .payout),
            Fixture.workingTuesday.key: day(Fixture.workingTuesday, minutes: -120, reason: .timeOffInLieu),
            Fixture.date(2026, 8, 5).key: day(Fixture.date(2026, 8, 5), minutes: 15, reason: .correction)
        ]
        let summary = engine.summary(
            in: CalendarDateRange(start: Fixture.workingMonday, end: Fixture.date(2026, 8, 5)),
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.adjustment(for: .payout), -600)
        XCTAssertEqual(summary.adjustment(for: .timeOffInLieu), -120)
        XCTAssertEqual(summary.adjustment(for: .correction), 15)
        XCTAssertEqual(summary.adjustmentMinutes, -705, "and still sum to the same total")
    }

    func testADayWithNoAdjustmentContributesNoReason() {
        let engine = Fixture.engine(calendar: calendar)
        let record = DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16))
        let summary = engine.summary(
            in: CalendarDateRange(single: Fixture.workingTuesday),
            records: [record.date.key: record],
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertTrue(summary.adjustmentsByReason.isEmpty)
    }

    func testAReportNamesThePayoutRatherThanShowingABareCorrection() {
        let settings = Fixture.settings()
        let range = CalendarDateRange(single: Fixture.workingTuesday)
        let record = day(Fixture.workingTuesday, minutes: -600, reason: .payout)
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: [record.date.key: record], holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "One day", countingThrough: Fixture.date(2026, 12, 31))

        let labels = table.totals.map(\.label)
        XCTAssertTrue(labels.contains("Paid out"))
        XCTAssertFalse(labels.contains("Time off in lieu"), "reasons with nothing against them are left out")
        XCTAssertEqual(table.totals.first { $0.label == "Paid out" }?.value, "-10h")
    }

    func testARecordWrittenBeforeReasonsExistedReadsAsACorrection() throws {
        let legacy = """
        {"date": 20260804, "adjustmentMinutes": -60, "note": "", "location": "", "tags": [], "isIncluded": true}
        """
        let record = try JSONDecoder().decode(DayRecord.self, from: Data(legacy.utf8))

        XCTAssertEqual(record.adjustmentMinutes, -60)
        XCTAssertEqual(record.adjustmentReason, .correction)
    }
}
