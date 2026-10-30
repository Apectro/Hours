import XCTest
@testable import Hours

/// The redesigned Insights' two new figures (1.2): hours by site, and the
/// running balance as a line through the period.
final class InsightsFiguresTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let siteA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let siteB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func worked(_ date: CalendarDate, _ start: Int, _ end: Int, endMinute: Int = 0, site: UUID?) -> Shift {
        Shift(start: Fixture.time(start), end: Fixture.time(end, endMinute), breaks: [BreakSpan.duration(30)], siteID: site)
    }

    private func days(_ records: [DayRecord], in range: CalendarDateRange) -> [DayComputation] {
        Fixture.engine(firstRecorded: range.start).days(
            in: range,
            records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }),
            holidays: []
        )
    }

    private var march: CalendarDateRange {
        CalendarDateRange(start: Fixture.date(2025, 3, 3), end: Fixture.date(2025, 3, 7))
    }

    // MARK: - By site

    func testHoursAddUpPerSiteLargestFirst() {
        let monday = Fixture.date(2025, 3, 3)
        let tuesday = Fixture.date(2025, 3, 4)
        let records = [
            // 07:00–11:00 on A (3h 30m after the break), 12:00–16:00 on B (3h 30m).
            DayRecord(date: monday, shifts: [worked(monday, 7, 11, site: siteA), worked(monday, 12, 16, site: siteB)]),
            // 07:00–16:00 on A: 8h 30m.
            DayRecord(date: tuesday, shifts: [worked(tuesday, 7, 16, site: siteA)]),
        ]
        let totals = SiteHours.totals(days(records, in: march), countingThrough: Fixture.date(2025, 3, 7))
        XCTAssertEqual(totals, [
            SiteHours.Total(siteID: siteA, workedMinutes: 210 + 510),
            SiteHours.Total(siteID: siteB, workedMinutes: 210),
        ])
    }

    func testHoursOfYourOwnAreNotASite() {
        let monday = Fixture.date(2025, 3, 3)
        let records = [DayRecord(date: monday, shifts: [worked(monday, 7, 16, site: nil)])]
        XCTAssertTrue(SiteHours.totals(days(records, in: march), countingThrough: Fixture.date(2025, 3, 7)).isEmpty)
    }

    // MARK: - The running balance as a line

    func testTheLineEndsAtTheRunningBalanceAndStepsBackByEachDay() {
        let monday = Fixture.date(2025, 3, 3)
        let tuesday = Fixture.date(2025, 3, 4)
        // Monday +2h (07:00–17:30 less 30m on an 8h day), Tuesday even,
        // Wednesday nothing: 8h short.
        let records = [
            DayRecord(date: monday, shifts: [worked(monday, 7, 17, endMinute: 30, site: nil)]),
            DayRecord(date: tuesday, shifts: [worked(tuesday, 8, 16, endMinute: 30, site: nil)]),
        ]
        let wednesday = Fixture.date(2025, 3, 5)
        let range = CalendarDateRange(start: monday, end: wednesday)
        let points = BalanceTrend.points(days: days(records, in: range), endingMinutes: -360, through: wednesday)

        XCTAssertEqual(points.map(\.date), [monday, tuesday, wednesday])
        XCTAssertEqual(points.map(\.minutes), [120, 120, -360])
    }

    func testTheLineStopsAtToday() {
        let monday = Fixture.date(2025, 3, 3)
        let points = BalanceTrend.points(days: days([], in: march), endingMinutes: 0, through: monday)
        XCTAssertEqual(points.map(\.date), [monday])
    }
}
