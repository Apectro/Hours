import XCTest
@testable import Hours

/// "Moved to another site…" with your clock running (1.2): the clock stops
/// at the time you left and starts again at the time you started on the
/// other site, so your own hours split where the site days do.
final class ClockFollowsMoveTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zagreb")!
        return calendar
    }

    private let today = CalendarDate(year: 2026, month: 10, day: 29)

    private func instant(_ hour: Int, _ minute: Int, on date: CalendarDate? = nil) -> Date {
        TimeOfDay(hour: hour, minute: minute).date(on: date ?? today, in: calendar)!
    }

    private func running(from hour: Int, _ minute: Int = 0, on date: CalendarDate? = nil) -> RunningShift {
        RunningShift(startingAt: instant(hour, minute, on: date), calendar: calendar)
    }

    func testTheClockStopsWhenYouLeftAndStartsWhenYouStarted() throws {
        let handover = try XCTUnwrap(ClockFollowsMove.handover(
            running: running(from: 7),
            youMoved: true,
            date: today,
            left: TimeOfDay(hour: 11, minute: 30),
            started: TimeOfDay(hour: 12, minute: 0),
            calendar: calendar
        ))

        XCTAssertEqual(handover.stopAt, instant(11, 30))
        XCTAssertEqual(handover.restartAt, instant(12, 0))
        // The shift the stop writes is the morning, as the site day says.
        let morning = running(from: 7).finished(at: handover.stopAt, calendar: calendar)
        XCTAssertEqual(morning.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(morning.end, TimeOfDay(hour: 11, minute: 30))
        // And the clock that starts again starts at noon.
        let afternoon = RunningShift(startingAt: handover.restartAt, calendar: calendar)
        XCTAssertEqual(afternoon.start, TimeOfDay(hour: 12, minute: 0))
        XCTAssertEqual(afternoon.date, today)
    }

    func testStartingStraightAwayStartsAgainAtTheSameMinute() throws {
        let handover = try XCTUnwrap(ClockFollowsMove.handover(
            running: running(from: 7), youMoved: true, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 11, minute: 30), calendar: calendar
        ))

        XCTAssertEqual(handover.stopAt, handover.restartAt)
    }

    func testNothingFollowsWhenYouStayed() {
        XCTAssertNil(ClockFollowsMove.handover(
            running: running(from: 7), youMoved: false, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), calendar: calendar
        ))
    }

    func testNothingFollowsWithoutARunningClock() {
        XCTAssertNil(ClockFollowsMove.handover(
            running: nil, youMoved: true, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), calendar: calendar
        ))
    }

    /// A move written for another day is not about the clock running now.
    func testAMoveOnAnotherDayLeavesTheClockAlone() {
        XCTAssertNil(ClockFollowsMove.handover(
            running: running(from: 7), youMoved: true, date: CalendarDate(year: 2026, month: 10, day: 28),
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), calendar: calendar
        ))
    }

    /// The clock started after you left: it is already the other site's.
    func testAClockStartedAfterYouLeftIsLeftAlone() {
        XCTAssertNil(ClockFollowsMove.handover(
            running: running(from: 12), youMoved: true, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), calendar: calendar
        ))
        XCTAssertNil(ClockFollowsMove.handover(
            running: running(from: 11, 30), youMoved: true, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), calendar: calendar
        ))
    }

    /// Started before left cannot be, and is read as starting when you left.
    func testAStartBeforeTheLeftTimeStartsWhenYouLeft() throws {
        let handover = try XCTUnwrap(ClockFollowsMove.handover(
            running: running(from: 7), youMoved: true, date: today,
            left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 11, minute: 0), calendar: calendar
        ))

        XCTAssertEqual(handover.restartAt, instant(11, 30))
    }
}
