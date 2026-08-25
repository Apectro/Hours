import XCTest
@testable import Hours

/// The two days a year when the clock and elapsed time disagree.
///
/// Neither answer is wrong, so the app has a setting; these tests pin down
/// what each choice actually does.
final class DaylightSavingTests: XCTestCase {
    private let calendar = Fixture.calendar(timeZone: Fixture.zagreb)

    func testTheTestCalendarActuallyObservesDaylightSaving() {
        let zone = calendar.timeZone
        XCTAssertNotEqual(
            zone.secondsFromGMT(for: Fixture.date(2026, 1, 15).date(in: calendar)),
            zone.secondsFromGMT(for: Fixture.date(2026, 7, 15).date(in: calendar)),
            "the fixture time zone must have a summer offset or these tests prove nothing"
        )
    }

    func testWallClockCountsEightHoursOnTheDayTheClocksGoForward() {
        let record = Fixture.record(on: Fixture.springForward, start: Fixture.time(0), end: Fixture.time(8))
        let result = Fixture.calculator(calendar: calendar).compute(record: record, on: Fixture.springForward)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertFalse(result.warnings.contains(.timeSkippedByClockChange))
    }

    func testElapsedTimeCountsSevenHoursOnTheDayTheClocksGoForward() {
        let settings = Fixture.settings(durationPolicy: .elapsedReal)
        let record = Fixture.record(on: Fixture.springForward, start: Fixture.time(0), end: Fixture.time(8))
        let result = Fixture.calculator(settings: settings, calendar: calendar)
            .compute(record: record, on: Fixture.springForward)

        XCTAssertEqual(result.workedMinutes, 420, "an hour of the shift did not happen")
    }

    func testWallClockCountsEightHoursOnTheDayTheClocksGoBack() {
        let record = Fixture.record(on: Fixture.fallBack, start: Fixture.time(0), end: Fixture.time(8))
        let result = Fixture.calculator(calendar: calendar).compute(record: record, on: Fixture.fallBack)

        XCTAssertEqual(result.workedMinutes, 480)
    }

    func testElapsedTimeCountsNineHoursOnTheDayTheClocksGoBack() {
        let settings = Fixture.settings(durationPolicy: .elapsedReal)
        let record = Fixture.record(on: Fixture.fallBack, start: Fixture.time(0), end: Fixture.time(8))
        let result = Fixture.calculator(settings: settings, calendar: calendar)
            .compute(record: record, on: Fixture.fallBack)

        XCTAssertEqual(result.workedMinutes, 540, "an hour was lived through twice")
    }

    func testATimeInsideTheSkippedHourDoesNotExist() {
        XCTAssertNil(
            TimeOfDay(hour: 2, minute: 30).date(on: Fixture.springForward, in: calendar),
            "02:30 never happens on this date"
        )
        XCTAssertNotNil(TimeOfDay(hour: 2, minute: 30).date(on: Fixture.fallBack, in: calendar))
    }

    func testAShiftStartingInTheSkippedHourFallsBackToTheWallClockAndSaysSo() {
        let settings = Fixture.settings(durationPolicy: .elapsedReal)
        let record = Fixture.record(
            on: Fixture.springForward,
            start: Fixture.time(2, 30),
            end: Fixture.time(10, 30)
        )
        let result = Fixture.calculator(settings: settings, calendar: calendar)
            .compute(record: record, on: Fixture.springForward)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertTrue(result.warnings.contains(.timeSkippedByClockChange))
    }

    func testAStoredDayNeverMovesAcrossAClockChange() {
        // Round-tripping through the calendar must land on the same date, which
        // is why the representative instant is noon rather than midnight.
        for date in [Fixture.springForward, Fixture.fallBack] {
            let instant = date.date(in: calendar)
            XCTAssertEqual(CalendarDate(instant, calendar: calendar), date)
        }
    }

    func testAnOvernightShiftAcrossTheAutumnChangeIsAnHourLonger() {
        let settings = Fixture.settings(durationPolicy: .elapsedReal)
        let evening = Fixture.date(2026, 10, 24)
        let record = Fixture.record(on: evening, start: Fixture.time(22), end: Fixture.time(6))
        let result = Fixture.calculator(settings: settings, calendar: calendar).compute(record: record, on: evening)

        XCTAssertEqual(result.workedMinutes, 540)
        XCTAssertTrue(result.crossesMidnight)
    }

    func testTheSameShiftInAZoneWithoutDaylightSavingIsUnaffected() {
        let settings = Fixture.settings(durationPolicy: .elapsedReal)
        let fixedZone = Fixture.calendar(timeZone: "UTC")
        let record = Fixture.record(on: Fixture.springForward, start: Fixture.time(0), end: Fixture.time(8))
        let result = Fixture.calculator(settings: settings, calendar: fixedZone)
            .compute(record: record, on: Fixture.springForward)

        XCTAssertEqual(result.workedMinutes, 480)
    }
}
