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

    // MARK: - What it says

    func testNothingMissingMeansNoNotification() {
        XCTAssertNil(GapFinder.message(for: [], formatting: formatting))
    }

    // The dates are written by the formatter rather than spelled out, because
    // how a locale abbreviates a date is Foundation's business and not this
    // test's subject — and the two platforms this suite runs on disagree about
    // it. On Apple's Foundation en_GB gives "Mon 3 Aug"; on Linux's it gives
    // "Mon, 3 Aug". What is being tested is the sentence built around them.

    func testOneMissingDayIsNamed() {
        let day = Fixture.workingMonday
        let message = GapFinder.message(for: [day], formatting: formatting)

        XCTAssertEqual(message, "\(formatting.mediumDate(day)) has no hours recorded.")
    }

    func testTwoMissingDaysAreBothNamed() {
        let first = Fixture.workingMonday
        let second = Fixture.workingTuesday
        let message = GapFinder.message(for: [first, second], formatting: formatting)

        XCTAssertEqual(
            message,
            "\(formatting.mediumDate(first)) and \(formatting.mediumDate(second)) have no hours recorded."
        )
        XCTAssertNotEqual(
            formatting.mediumDate(first),
            formatting.mediumDate(second),
            "both days have to be named, so they must be distinguishable"
        )
    }

    func testManyMissingDaysAreCounted() {
        let dates = [3, 4, 5, 6].map { Fixture.date(2026, 8, $0) }
        let message = GapFinder.message(for: dates, formatting: formatting)

        // The count, and only the first date: naming four is a notification
        // nobody reads to the end of.
        XCTAssertEqual(
            message,
            "4 days have no hours recorded, starting \(formatting.mediumDate(dates[0]))."
        )
    }

    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)
    }
}
