import XCTest
import SwiftData
@testable import Hours

/// Starting and stopping the clock.
@MainActor
final class TimeClockTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func makeClock(settings: AppSettings = Fixture.settings()) -> (TimeClock, ActiveShiftStore, WorkdayRepository) {
        let container = HoursModelContainer.ephemeral()
        let repository = WorkdayRepository(context: ModelContext(container))
        let store = ActiveShiftStore.ephemeral()
        let clock = TimeClock(repository: repository, clock: store, settings: settings, calendar: calendar)
        return (clock, store, repository)
    }

    /// 08:00 on Tuesday 4 August 2026, in the fixture's time zone.
    private func instant(hour: Int, minute: Int = 0, day: Int = 4) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    // MARK: - Turning a running clock into a shift

    func testStoppingTheClockRecordsTheHours() {
        let (clock, _, repository) = makeClock()

        clock.clockIn(at: instant(hour: 8))
        let result = clock.clockOut(at: instant(hour: 16, minute: 30))

        guard case let .recorded(date, worked, capped) = result else {
            return XCTFail("expected the shift to be recorded")
        }
        XCTAssertEqual(date, Fixture.workingTuesday)
        XCTAssertEqual(worked, 510)
        XCTAssertFalse(capped)

        let stored = repository.record(on: Fixture.workingTuesday)
        XCTAssertEqual(stored?.shifts.count, 1)
        XCTAssertEqual(stored?.shifts.first?.start, Fixture.time(8))
        XCTAssertEqual(stored?.shifts.first?.end, Fixture.time(16, 30))
    }

    func testClockingInAndOutTwiceInADayMakesASplitShiftRatherThanLosingTheMorning() {
        let (clock, _, repository) = makeClock()

        clock.clockIn(at: instant(hour: 8))
        clock.clockOut(at: instant(hour: 12))
        clock.clockIn(at: instant(hour: 13))
        clock.clockOut(at: instant(hour: 17))

        let stored = repository.record(on: Fixture.workingTuesday)
        XCTAssertEqual(stored?.shifts.count, 2)
        XCTAssertEqual(stored?.shifts.first?.start, Fixture.time(8))
        XCTAssertEqual(stored?.shifts.last?.end, Fixture.time(17))
    }

    func testStoppingAClockStartedYesterdayRecordsItAgainstYesterday() {
        let (clock, _, repository) = makeClock()

        clock.clockIn(at: instant(hour: 22, day: 4))
        let result = clock.clockOut(at: instant(hour: 6, day: 5))

        guard case let .recorded(date, worked, _) = result else {
            return XCTFail("expected the shift to be recorded")
        }
        XCTAssertEqual(date, Fixture.workingTuesday, "the day it started, not the day it ended")
        XCTAssertEqual(worked, 480)

        let stored = repository.record(on: Fixture.workingTuesday)
        XCTAssertEqual(stored?.shifts.first?.end, Fixture.time(6))
        XCTAssertNil(repository.record(on: Fixture.date(2026, 8, 5)))
    }

    // MARK: - Guards

    func testStartingATwiceDoesNotDiscardTheShiftInProgress() {
        let (clock, store, _) = makeClock()

        let first = clock.clockIn(at: instant(hour: 8))
        let second = clock.clockIn(at: instant(hour: 9))

        XCTAssertNotNil(first)
        XCTAssertNil(second, "a second tap must not silently restart the clock")
        XCTAssertEqual(store.running?.start, Fixture.time(8))
    }

    func testStoppingWithNothingRunningDoesNothing() {
        let (clock, _, repository) = makeClock()

        XCTAssertEqual(clock.clockOut(at: instant(hour: 17)), .nothingRunning)
        XCTAssertNil(repository.record(on: Fixture.workingTuesday))
    }

    func testDiscardingRecordsNothing() {
        let (clock, store, repository) = makeClock()

        clock.clockIn(at: instant(hour: 8))
        clock.discard()

        XCTAssertNil(store.running)
        XCTAssertNil(repository.record(on: Fixture.workingTuesday))
    }

    func testAClockLeftRunningForDaysIsCappedRatherThanRecordingNonsense() {
        let (clock, _, _) = makeClock()

        clock.clockIn(at: instant(hour: 8, day: 4))
        let result = clock.clockOut(at: instant(hour: 8, day: 7))

        guard case let .recorded(_, worked, capped) = result else {
            return XCTFail("expected the shift to be recorded")
        }
        XCTAssertTrue(capped)
        XCTAssertLessThanOrEqual(worked, 24 * 60)
    }

    // MARK: - The running shift itself

    func testElapsedTimeIsRealTimeNotWallClock() {
        let shift = RunningShift(startingAt: instant(hour: 8), calendar: calendar)

        XCTAssertEqual(shift.elapsedSeconds(at: instant(hour: 8)), 0)
        XCTAssertEqual(shift.elapsedMinutes(at: instant(hour: 10, minute: 30)), 150)
        XCTAssertEqual(shift.elapsedSeconds(at: instant(hour: 7)), 0, "never negative")
    }

    func testAShiftRemembersTheDayAndTimeItStarted() {
        let shift = RunningShift(startingAt: instant(hour: 8, minute: 45), calendar: calendar)

        XCTAssertEqual(shift.date, Fixture.workingTuesday)
        XCTAssertEqual(shift.start, Fixture.time(8, 45))
    }

    func testTheProjectedTotalMatchesWhatStoppingWouldRecord() {
        let (clock, _, _) = makeClock()
        clock.clockIn(at: instant(hour: 8))

        let projected = clock.projectedWorkedMinutes(at: instant(hour: 16, minute: 30))
        XCTAssertEqual(projected, 510)
    }

    func testARunningShiftSurvivesBeingWrittenAndReadBack() throws {
        let shift = RunningShift(startingAt: instant(hour: 8), calendar: calendar, jobID: Job.primaryID)
        let restored = try JSONDecoder().decode(RunningShift.self, from: try JSONEncoder().encode(shift))

        XCTAssertEqual(restored, shift)
    }

    func testTheClockFormatsAsATickingDuration() {
        XCTAssertEqual(ClockCard.clockString(0), "0:00:00")
        XCTAssertEqual(ClockCard.clockString(59), "0:00:59")
        XCTAssertEqual(ClockCard.clockString(3661), "1:01:01")
        XCTAssertEqual(ClockCard.clockString(36000), "10:00:00")
    }
}
