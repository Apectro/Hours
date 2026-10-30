import XCTest
@testable import Hours

/// The sites a crew sheet ticks by itself for a month, and the months the
/// Sites list offers a sheet for.
final class CrewSheetSitesTests: XCTestCase {
    private let trg = UUID()
    private let jarun = UUID()
    private let other = UUID()
    private var order: [UUID] { [trg, jarun, other] }

    func testEverySiteWorkedThatMonthIsTicked() {
        let worked = [jarun: 600, trg: 9_000]
        XCTAssertEqual(CrewSheetSites.ticked(worked: worked, order: order, opened: nil), [trg, jarun])
    }

    /// A day rained off is a day on the site, though nobody earned minutes.
    func testASiteWithOnlyAZeroDayCounts() {
        XCTAssertEqual(CrewSheetSites.ticked(worked: [other: 0], order: order, opened: nil), [other])
    }

    func testTheSiteItWasOpenedFromStaysFirst() {
        let worked = [trg: 9_000, jarun: 600]
        XCTAssertEqual(CrewSheetSites.ticked(worked: worked, order: order, opened: jarun), [jarun, trg])
    }

    /// Opened from a site with nothing that month: that site alone, not
    /// whatever the others did.
    func testASiteWithNothingThatMonthStaysAlone() {
        XCTAssertEqual(CrewSheetSites.ticked(worked: [trg: 9_000], order: order, opened: other), [other])
    }

    func testNothingWorkedLeavesTheTicksAlone() {
        XCTAssertEqual(CrewSheetSites.ticked(worked: [:], order: order, opened: nil), [])
    }

    func testMonthsAreNewestFirstAndOnlyThoseWithWork() {
        let today = Fixture.date(2026, 10, 30)
        let worked: Set = [YearMonth(year: 2026, month: 10), YearMonth(year: 2026, month: 8), YearMonth(year: 2026, month: 5)]
        XCTAssertEqual(
            CrewSheetSites.months(worked: worked, today: today, limit: 3),
            [YearMonth(year: 2026, month: 10), YearMonth(year: 2026, month: 8)]
        )
    }

    func testMonthsCrossTheYear() {
        let today = Fixture.date(2027, 1, 5)
        let worked: Set = [YearMonth(year: 2026, month: 12)]
        XCTAssertEqual(CrewSheetSites.months(worked: worked, today: today, limit: 3), [YearMonth(year: 2026, month: 12)])
    }
}
