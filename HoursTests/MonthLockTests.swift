import XCTest
@testable import Hours

/// Which months refuse edits, and what a refusal says.
final class MonthLockTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = YearMonth(year: 2026, month: 8)
    private let september = YearMonth(year: 2026, month: 9)

    private var locked: MonthLock { MonthLock(months: [august]) }

    func testNothingIsLockedByDefault() {
        XCTAssertFalse(MonthLock.unlocked.isLocked(august))
        XCTAssertFalse(MonthLock.unlocked.isLocked(Fixture.workingMonday))
        XCTAssertNoThrow(try MonthLock.unlocked.check(Fixture.workingMonday))
    }

    func testALockedMonthCoversEveryDayInIt() {
        for day in [1, 15, 31] {
            let date = CalendarDate(year: 2026, month: 8, day: day)
            XCTAssertTrue(locked.isLocked(date), "\(date) should be closed")
            XCTAssertThrowsError(try locked.check(date))
        }
    }

    /// The boundaries either side. A lock that leaked into the last day of
    /// July or the first of September would be discovered by somebody unable
    /// to record a shift, with nothing on screen explaining why.
    func testTheMonthEitherSideIsUntouched() {
        for date in [
            CalendarDate(year: 2026, month: 7, day: 31),
            CalendarDate(year: 2026, month: 9, day: 1),
            CalendarDate(year: 2025, month: 8, day: 15),
        ] {
            XCTAssertFalse(locked.isLocked(date), "\(date) is not in a closed month")
            XCTAssertNoThrow(try locked.check(date))
        }
    }

    /// The refusal names the month. An error saying only "refused" leaves the
    /// person to guess which of a year's edits they are being stopped from.
    func testARefusalNamesTheMonth() {
        XCTAssertThrowsError(try locked.check(CalendarDate(year: 2026, month: 8, day: 4))) { error in
            XCTAssertEqual(error as? MonthLock.Refusal, .monthIsClosed(self.august))
        }
    }

    func testLockingAndReopening() {
        var lock = MonthLock()
        lock.lock(august)
        XCTAssertTrue(lock.isLocked(august))

        lock.lock(august)
        XCTAssertEqual(lock.months.count, 1, "locking twice is not two locks")

        lock.unlock(august)
        XCTAssertFalse(lock.isLocked(august))

        lock.unlock(september)
        XCTAssertTrue(lock.months.isEmpty, "reopening a month that was never closed is not an error")
    }

    // MARK: - What a range says

    /// A bulk edit needs every closed month in its range, not merely whether
    /// one exists — nothing is changed when any of them is closed, so naming
    /// all of them saves a second attempt.
    func testARangeReportsEveryClosedMonthItTouches() {
        let lock = MonthLock(months: [august, YearMonth(year: 2026, month: 10)])
        let range = CalendarDateRange(
            start: CalendarDate(year: 2026, month: 7, day: 20),
            end: CalendarDate(year: 2026, month: 11, day: 5)
        )

        XCTAssertEqual(
            lock.lockedMonths(in: range, calendar: calendar),
            [august, YearMonth(year: 2026, month: 10)],
            "both closed months are in range and both should be named, in order"
        )
    }

    func testARangeInsideOneOpenMonthReportsNothing() {
        let range = CalendarDateRange(
            start: CalendarDate(year: 2026, month: 9, day: 1),
            end: CalendarDate(year: 2026, month: 9, day: 30)
        )
        XCTAssertTrue(locked.lockedMonths(in: range, calendar: calendar).isEmpty)
    }

    /// A single day inside a closed month is still a range that touches it.
    /// The loop runs from the start month to the end month inclusive, and an
    /// exclusive bound here would let every one-day edit through.
    func testASingleDayRangeInAClosedMonthIsCaught() {
        let day = CalendarDate(year: 2026, month: 8, day: 4)
        let range = CalendarDateRange(start: day, end: day)

        XCTAssertEqual(locked.lockedMonths(in: range, calendar: calendar), [august])
    }

    func testARangeCrossingAYearEndWalksThroughJanuary() {
        let lock = MonthLock(months: [YearMonth(year: 2027, month: 1)])
        let range = CalendarDateRange(
            start: CalendarDate(year: 2026, month: 12, day: 20),
            end: CalendarDate(year: 2027, month: 2, day: 10)
        )

        XCTAssertEqual(
            lock.lockedMonths(in: range, calendar: calendar),
            [YearMonth(year: 2027, month: 1)],
            "the walk must roll the year over rather than stopping at December"
        )
    }

    /// Storage round trip. The lock is a `Set` in a `Codable` struct, and a
    /// lock that does not survive being written and read back is a lock that
    /// quietly disappears the next time the app launches.
    func testTheLockSurvivesEncodingAndDecoding() throws {
        let original = MonthLock(months: [august, YearMonth(year: 2025, month: 12)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MonthLock.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isLocked(august))
    }

    /// Settings written before month locking existed must still open, with
    /// nothing locked — the lenient decoder is what makes that true, and it is
    /// worth an assertion rather than an assumption.
    func testSettingsFromBeforeTheFeatureDecodeWithNothingLocked() throws {
        let json = Data(#"{"schemaVersion": 1}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertTrue(settings.monthLock.months.isEmpty)
        XCTAssertFalse(settings.carryOver.isEnabled)
        XCTAssertTrue(settings.yearCloses.isEmpty)
    }
}
