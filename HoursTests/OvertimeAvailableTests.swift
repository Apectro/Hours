import XCTest
@testable import Hours

/// "Overtime available: +12h 30m · about 1.5 days off": the running balance
/// read as days, using the length of a working day in the week in force.
final class OvertimeAvailableTests: XCTestCase {
    private let date = Fixture.workingTuesday

    func testABalanceIsReadAsDaysOfTheScheduleInForce() {
        let available = OvertimeAvailable(balanceMinutes: 750, on: date, settings: Fixture.settings())
        XCTAssertEqual(available?.minutes, 750)
        XCTAssertEqual(available?.dayMinutes, 480)
        XCTAssertEqual(available?.daysOff, HalfDays(halves: 3), "12h 30m of 8-hour days is about one and a half")
        XCTAssertEqual(available?.daysOff?.formatted(), "1.5")
    }

    func testItRoundsToTheNearestHalfDay() {
        let settings = Fixture.settings()
        XCTAssertEqual(OvertimeAvailable(balanceMinutes: 100, on: date, settings: settings)?.daysOff, HalfDays(halves: 0))
        XCTAssertEqual(OvertimeAvailable(balanceMinutes: 120, on: date, settings: settings)?.daysOff, HalfDays(halves: 1))
        XCTAssertEqual(OvertimeAvailable(balanceMinutes: 1440, on: date, settings: settings)?.daysOff, HalfDays(days: 3))
    }

    func testAnUnevenWeekUsesItsAverageWorkingDay() {
        // 9, 9, 9, 9 and a 4-hour Friday: 40 hours over five days.
        let schedule = WorkSchedule(minutesByWeekday: [0, 540, 540, 540, 540, 240, 0])
        let available = OvertimeAvailable(balanceMinutes: 960, on: date, settings: Fixture.settings(schedule: schedule))
        XCTAssertEqual(available?.dayMinutes, 480)
        XCTAssertEqual(available?.daysOff, HalfDays(days: 2))
    }

    func testTheWeekInForceOnTheDayIsTheOneUsed() {
        var settings = Fixture.settings()
        settings.changePrimarySchedule(
            to: WorkSchedule(minutesByWeekday: [0, 600, 600, 600, 600, 0, 0]),
            from: Fixture.date(2026, 9, 1)
        )
        XCTAssertEqual(OvertimeAvailable(balanceMinutes: 1200, on: date, settings: settings)?.dayMinutes, 480)
        XCTAssertEqual(OvertimeAvailable(balanceMinutes: 1200, on: Fixture.date(2026, 9, 2), settings: settings)?.daysOff, HalfDays(days: 2))
    }

    func testNothingIsAvailableAtOrBelowZero() {
        XCTAssertNil(OvertimeAvailable(balanceMinutes: 0, on: date, settings: Fixture.settings()))
        XCTAssertNil(OvertimeAvailable(balanceMinutes: -30, on: date, settings: Fixture.settings()))
    }

    func testWithNoWorkingDaysThereAreNoDaysToSpeakOf() {
        let none = WorkSchedule(minutesByWeekday: [0, 0, 0, 0, 0, 0, 0])
        let available = OvertimeAvailable(balanceMinutes: 600, on: date, settings: Fixture.settings(schedule: none))
        XCTAssertEqual(available?.minutes, 600)
        XCTAssertNil(available?.daysOff)
    }

    /// Taking the days off really does spend the balance: one time-off-in-lieu
    /// day takes exactly one working day's hours.
    func testADayOfTimeOffInLieuSpendsOneDayOfIt() {
        let settings = Fixture.settings()
        let engine = Fixture.engine(settings: settings)
        let toil = engine.day(date, record: DayRecord(date: date, dayTypeID: .timeOffInLieu), holidays: [])
        let available = OvertimeAvailable(balanceMinutes: 960, on: date, settings: settings)!
        let afterwards = OvertimeAvailable(balanceMinutes: 960 + toil.balanceMinutes, on: date, settings: settings)
        XCTAssertEqual(afterwards?.daysOff, HalfDays(halves: available.daysOff!.halves - 2))
    }
}
