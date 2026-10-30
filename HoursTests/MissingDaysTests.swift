import XCTest
@testable import Hours

/// Which days are "not written": one definition, shared by the calendar's
/// banner, the site's month strip and the export's warning, and the same as
/// the gap reminder's.
final class MissingDaysTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Friday 14 August 2026.
    private let today = Fixture.date(2026, 8, 14)
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func missing(
        records: [DayRecord] = [],
        holidays: [HolidayRule] = [],
        settings: AppSettings = Fixture.settings(),
        range: CalendarDateRange? = nil,
        firstRecorded: CalendarDate? = Fixture.longAgo
    ) -> [CalendarDate] {
        MissingDays.personal(
            records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }),
            holidays: holidays,
            settings: settings,
            calendar: calendar,
            range: range ?? august,
            today: today,
            firstRecorded: firstRecorded
        )
    }

    func testPastWorkingDaysWithNothingAreMissing() {
        let days = missing()

        // Monday 3rd to Thursday 13th: nine working days before today.
        XCTAssertEqual(days.count, 9)
        XCTAssertEqual(days.first, Fixture.workingMonday)
        XCTAssertEqual(days.last, Fixture.date(2026, 8, 13))
    }

    func testTodayAndTheFutureNeverCount() {
        let days = missing()

        XCTAssertFalse(days.contains(today), "today is not over yet")
        XCTAssertFalse(days.contains { $0 > today })
    }

    func testDaysOffAreNotMissing() {
        let days = missing()

        XCTAssertFalse(days.contains(Fixture.saturday))
        XCTAssertFalse(days.contains(Fixture.date(2026, 8, 9)))
    }

    func testAWrittenDayIsNotMissing() {
        let worked = Fixture.record(on: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16))

        XCTAssertFalse(missing(records: [worked]).contains(Fixture.workingMonday))
        XCTAssertEqual(missing(records: [worked]).count, 8)
    }

    func testLeaveIsNotMissing() {
        let leave = Fixture.record(on: Fixture.workingMonday, type: .vacation)

        XCTAssertFalse(missing(records: [leave]).contains(Fixture.workingMonday))
    }

    func testAPublicHolidayIsNotMissing() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 5))

        XCTAssertFalse(missing(holidays: [holiday]).contains(Fixture.date(2026, 8, 5)))
    }

    func testAnExcludedDayIsNotMissing() {
        var excluded = DayRecord(date: Fixture.workingMonday)
        excluded.isIncluded = false

        XCTAssertFalse(missing(records: [excluded]).contains(Fixture.workingMonday))
    }

    func testDaysBeforeTheBalanceStartsAreNotMissing() {
        var settings = Fixture.settings()
        settings.balanceStartDate = Fixture.date(2026, 8, 10)

        XCTAssertEqual(missing(settings: settings).first, Fixture.date(2026, 8, 10))
        XCTAssertEqual(missing(firstRecorded: nil), [], "nothing recorded ever, nothing counted")
    }

    func testOnlyTheRangeIsLookedAt() {
        let week = CalendarDateRange(start: Fixture.date(2026, 8, 10), end: Fixture.date(2026, 8, 16))

        XCTAssertEqual(missing(range: week), (10...13).map { Fixture.date(2026, 8, $0) })
    }

    func testAgreesWithTheGapReminder() {
        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)
        let computed = Fixture.engine(calendar: calendar).days(in: window, records: [:], holidays: [])

        XCTAssertEqual(
            MissingDays.personal(days: computed, today: today),
            GapFinder.unrecordedWorkingDays(in: computed, asOf: today)
        )
        XCTAssertEqual(missing(range: window), GapFinder.unrecordedWorkingDays(in: computed, asOf: today))
    }
}
