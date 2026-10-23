import XCTest
@testable import Hours

/// Export's ‹ › arrows: a whole period at a time, never into a period that
/// has not started yet, and the calendar's month menu offering to close or
/// reopen the month on screen.
final class PeriodSteppingTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let today = CalendarDate(year: 2026, month: 10, day: 23)

    // MARK: - Stepping

    func testADayStepsOneDay() {
        let anchor = CalendarDate(year: 2026, month: 10, day: 1)
        XCTAssertEqual(ExportRangeKind.day.step(anchor, by: -1, calendar: calendar), CalendarDate(year: 2026, month: 9, day: 30))
        XCTAssertEqual(ExportRangeKind.day.step(anchor, by: 1, calendar: calendar), CalendarDate(year: 2026, month: 10, day: 2))
    }

    func testAWeekStepsSevenDays() {
        let anchor = CalendarDate(year: 2026, month: 10, day: 23)
        XCTAssertEqual(ExportRangeKind.week.step(anchor, by: -1, calendar: calendar), CalendarDate(year: 2026, month: 10, day: 16))
    }

    /// The 31st into a 30-day month lands on its last day, not on the 1st of
    /// the month after, which would skip a month.
    func testAMonthStepKeepsTheDayInsideTheMonth() {
        let anchor = CalendarDate(year: 2026, month: 10, day: 31)
        XCTAssertEqual(ExportRangeKind.month.step(anchor, by: -1, calendar: calendar), CalendarDate(year: 2026, month: 9, day: 30))
        XCTAssertEqual(ExportRangeKind.month.step(anchor, by: 1, calendar: calendar), CalendarDate(year: 2026, month: 11, day: 30))
        XCTAssertEqual(
            ExportRangeKind.month.step(CalendarDate(year: 2026, month: 1, day: 15), by: -1, calendar: calendar),
            CalendarDate(year: 2025, month: 12, day: 15)
        )
    }

    func testAYearStepKeepsTheLeapDayInsideFebruary() {
        let anchor = CalendarDate(year: 2028, month: 2, day: 29)
        XCTAssertEqual(ExportRangeKind.year.step(anchor, by: -1, calendar: calendar), CalendarDate(year: 2027, month: 2, day: 28))
    }

    func testACustomRangeDoesNotStep() {
        XCTAssertFalse(ExportRangeKind.custom.steps)
        XCTAssertTrue(ExportRangeKind.month.steps)
        XCTAssertEqual(ExportRangeKind.custom.step(today, by: -1, calendar: calendar), today)
    }

    // MARK: - Not into the future

    func testForwardStopsAtThePeriodHoldingToday() {
        XCTAssertFalse(ExportRangeKind.day.canStepForward(from: today, today: today, calendar: calendar))
        XCTAssertTrue(ExportRangeKind.day.canStepForward(from: today.adding(days: -1, in: calendar), today: today, calendar: calendar))

        XCTAssertFalse(ExportRangeKind.week.canStepForward(from: today, today: today, calendar: calendar))
        // Monday of this week, from last week's Friday.
        XCTAssertTrue(ExportRangeKind.week.canStepForward(from: CalendarDate(year: 2026, month: 10, day: 16), today: today, calendar: calendar))

        XCTAssertFalse(ExportRangeKind.month.canStepForward(from: CalendarDate(year: 2026, month: 10, day: 1), today: today, calendar: calendar))
        XCTAssertTrue(ExportRangeKind.month.canStepForward(from: CalendarDate(year: 2026, month: 9, day: 30), today: today, calendar: calendar))

        XCTAssertFalse(ExportRangeKind.year.canStepForward(from: today, today: today, calendar: calendar))
        XCTAssertTrue(ExportRangeKind.year.canStepForward(from: CalendarDate(year: 2025, month: 12, day: 31), today: today, calendar: calendar))

        XCTAssertFalse(ExportRangeKind.custom.canStepForward(from: CalendarDate(year: 2020, month: 1, day: 1), today: today, calendar: calendar))
    }

    /// A week that starts on Monday the 19th is reachable from the week
    /// before even on Monday itself.
    func testTheWeekThatStartsTodayIsReachable() {
        let monday = CalendarDate(year: 2026, month: 10, day: 19)
        XCTAssertTrue(ExportRangeKind.week.canStepForward(from: CalendarDate(year: 2026, month: 10, day: 12), today: monday, calendar: calendar))
    }

    // MARK: - Closing from the calendar

    func testAFinishedOpenMonthOffersClosing() {
        let september = YearMonth(year: 2026, month: 9)
        XCTAssertEqual(MonthLock().offer(for: september, today: today), .close)
    }

    func testAClosedMonthOffersReopening() {
        let september = YearMonth(year: 2026, month: 9)
        XCTAssertEqual(MonthLock(months: [september]).offer(for: september, today: today), .reopen)
        // Even the month still running, if it was closed somehow (a restore,
        // another device): it must always be possible to undo.
        let october = YearMonth(year: 2026, month: 10)
        XCTAssertEqual(MonthLock(months: [october]).offer(for: october, today: today), .reopen)
    }

    /// Only a finished month can be closed, as in Settings: closing the month
    /// you are still in would refuse today's hours.
    func testTheRunningMonthAndLaterOfferNothing() {
        XCTAssertNil(MonthLock().offer(for: YearMonth(year: 2026, month: 10), today: today))
        XCTAssertNil(MonthLock().offer(for: YearMonth(year: 2026, month: 12), today: today))
    }
}
