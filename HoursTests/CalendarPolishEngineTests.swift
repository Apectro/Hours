import XCTest
@testable import Hours

/// The calendar after the owner's first look (2026-11): which days get a
/// tile (the neighbouring months' too), which rows have no tile at all and
/// so are drawn shorter, and the week total in the app's duration format.
final class CalendarPolishEngineTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// November 2026 starts on a Sunday and ends on a Monday: six rows,
    /// 26 October to 6 December.
    private func november() -> MonthLayout {
        MonthLayout.make(month: YearMonth(year: 2026, month: 11), calendar: calendar, includesWeekends: true)
    }

    private func worked(_ date: CalendarDate) -> DayRecord {
        DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])
    }

    private func computations(_ records: [DayRecord], layout: MonthLayout) -> [Int: DayComputation] {
        var byKey: [Int: DayRecord] = [:]
        for record in records { byKey[record.date.key] = record }
        let days = Fixture.engine(calendar: calendar).days(
            in: CalendarWeekTotals.span(of: layout, calendar: calendar),
            records: byKey,
            holidays: []
        )
        var result: [Int: DayComputation] = [:]
        for day in days { result[day.date.key] = day }
        return result
    }

    // MARK: - A day's look

    func testAWrittenDayHasATile() {
        let layout = november()
        let date = Fixture.date(2026, 11, 3)
        let days = computations([worked(date)], layout: layout)

        let look = CalendarDayLook.of(days[date.key], today: Fixture.date(2026, 11, 20))

        XCTAssertEqual(look, .written)
        XCTAssertTrue(look.hasTile)
    }

    func testAMissedWorkingDayHasATileAndAWeekendHasNone() {
        let layout = november()
        let days = computations([], layout: layout)
        let today = Fixture.date(2026, 11, 20)

        XCTAssertEqual(CalendarDayLook.of(days[Fixture.date(2026, 11, 3).key], today: today), .missing)
        XCTAssertEqual(CalendarDayLook.of(days[Fixture.date(2026, 11, 7).key], today: today), .dayOff)
        XCTAssertFalse(CalendarDayLook.dayOff.hasTile)
        XCTAssertFalse(CalendarDayLook.plain.hasTile)
    }

    func testLeaveHasATile() {
        let layout = november()
        let date = Fixture.date(2026, 11, 4)
        let days = computations([DayRecord(date: date, dayTypeID: .vacation)], layout: layout)

        let look = CalendarDayLook.of(days[date.key], today: Fixture.date(2026, 11, 2))

        XCTAssertEqual(look, .away)
        XCTAssertTrue(look.hasTile)
    }

    func testADayToComeWithNothingOnItHasNoTile() {
        let layout = november()
        let days = computations([], layout: layout)

        XCTAssertEqual(CalendarDayLook.of(days[Fixture.date(2026, 11, 25).key], today: Fixture.date(2026, 11, 4)), .plain)
        XCTAssertEqual(CalendarDayLook.of(nil, today: Fixture.date(2026, 11, 4)), .plain)
    }

    // MARK: - Short rows

    func testRowsWithNoTileAtAllAreShort() {
        let layout = november()
        let today = Fixture.date(2026, 11, 4)
        let days = computations([worked(Fixture.date(2026, 10, 27))], layout: layout)

        let short = CalendarWeekTotals.shortRows(of: layout, computations: days, today: today)

        XCTAssertEqual(short.count, 6)
        // Row 0 has 26–31 October (missed or written) and today's row has
        // tiles; the rows still to come have none.
        XCTAssertEqual(short, [false, false, true, true, true, true])
    }

    func testARowWithOneTileToComeIsNotShort() {
        let layout = november()
        let today = Fixture.date(2026, 11, 4)
        let days = computations([DayRecord(date: Fixture.date(2026, 11, 25), dayTypeID: .vacation)], layout: layout)

        let short = CalendarWeekTotals.shortRows(of: layout, computations: days, today: today)

        XCTAssertEqual(short[4], false, "booked leave on the 25th")
        XCTAssertEqual(short[3], true)
    }

    func testTodaysRowIsNeverShort() {
        let layout = november()
        // Before the balance starts nothing is missing, so only today has a tile.
        let engine = Fixture.engine(calendar: calendar, firstRecorded: Fixture.date(2026, 12, 1))
        let resolved = engine.days(in: CalendarWeekTotals.span(of: layout, calendar: calendar), records: [:], holidays: [])
        var days: [Int: DayComputation] = [:]
        for day in resolved { days[day.date.key] = day }

        let short = CalendarWeekTotals.shortRows(of: layout, computations: days, today: Fixture.date(2026, 11, 18))

        XCTAssertEqual(short[3], false)
        XCTAssertEqual(short[2], true)
    }

    // MARK: - The week total's text

    func testTheWeekTotalIsInTheAppsDurationFormat() {
        let hoursAndMinutes = DurationFormatting(style: .hoursAndMinutes)

        XCTAssertEqual(
            CalendarWeekTotals.label(2658, formatting: hoursAndMinutes),
            hoursAndMinutes.string(2658),
            "the same text as This week"
        )
    }

    func testAnEmptyWeekHasNoTotal() {
        XCTAssertNil(CalendarWeekTotals.label(0, formatting: DurationFormatting(style: .hoursAndMinutes)))
    }
}
