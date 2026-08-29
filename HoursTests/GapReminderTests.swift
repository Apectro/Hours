import XCTest
@testable import Hours

/// Finding days with nothing recorded.
final class GapReminderTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let today = Fixture.date(2026, 8, 14)

    private func days(records: [Int: DayRecord], holidays: [HolidayRule] = []) -> [DayComputation] {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 14))
        return Fixture.engine(calendar: calendar).days(in: range, records: records, holidays: holidays)
    }

    func testAWorkingDayWithNothingOnItIsAGap() {
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:]), asOf: today)

        // Monday 3rd to Thursday 13th: nine working days before today.
        XCTAssertEqual(gaps.count, 9)
        XCTAssertTrue(gaps.contains(Fixture.workingMonday))
        XCTAssertFalse(gaps.contains(today), "today is not over yet")
    }

    func testWeekendsAreNeverGaps() {
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 8)))
        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 9)))
    }

    func testARecordedDayIsNotAGap() {
        let worked = DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16))
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [worked.date.key: worked]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
        XCTAssertEqual(gaps.count, 8)
    }

    func testADayOfLeaveIsNotAGap() {
        let leave = DayRecord(date: Fixture.workingMonday, dayTypeID: .vacation)
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [leave.date.key: leave]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
    }

    func testAPublicHolidayIsNotAGap() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 5))
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:], holidays: [holiday]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 5)))
    }

    func testAnExcludedDayIsNotAGap() {
        var excluded = DayRecord(date: Fixture.workingMonday)
        excluded.isIncluded = false
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [excluded.date.key: excluded]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
    }

    // MARK: - The window

    func testTheWindowEndsYesterday() {
        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)

        XCTAssertEqual(window.end, Fixture.date(2026, 8, 13))
        XCTAssertEqual(window.start, Fixture.date(2026, 7, 31))
        XCTAssertFalse(window.contains(today))
    }
}
