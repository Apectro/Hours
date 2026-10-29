import XCTest
@testable import Hours

/// Your calendar day after working on two sites: one row per site and a
/// thin bar with a colour per site and a gap between them.
final class DaySiteSplitTests: XCTestCase {
    private let date = Fixture.workingTuesday
    private let here = UUID()
    private let there = UUID()

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func day(_ shifts: [Shift]) -> DayComputation {
        WorkdayCalculator(settings: Fixture.settings(), calendar: Fixture.calendar())
            .compute(record: DayRecord(date: date, shifts: shifts), on: date)
    }

    private func siteShift(_ site: UUID, _ start: TimeOfDay, _ end: TimeOfDay, breakMinutes: Int = 0) -> Shift {
        Shift(
            id: site,
            start: start,
            end: end,
            breaks: breakMinutes > 0 ? [BreakSpan(id: site, explicitMinutes: breakMinutes)] : [],
            siteID: site
        )
    }

    func testTwoSitesGiveARowEachAndABarWithTheGapBetween() throws {
        let split = try XCTUnwrap(DaySiteSplit.make(day([
            siteShift(there, time(12), time(16), breakMinutes: 30),
            siteShift(here, time(7), time(11, 30))
        ])))

        XCTAssertEqual(split.parts.map(\.siteID), [here, there], "in the order worked")
        XCTAssertEqual(split.parts.map(\.workedMinutes), [270, 210])
        XCTAssertEqual(split.parts.map(\.breakMinutes), [0, 30])
        XCTAssertEqual(split.segments, [.site(0, minutes: 270), .gap(minutes: 30), .site(1, minutes: 240)])
        XCTAssertEqual(split.breakSiteID, there, "the break was taken on one site")
        XCTAssertEqual(split.start, time(7))
        XCTAssertEqual(split.end, time(16))
    }

    func testABreakOnBothSitesBelongsToNeither() throws {
        let split = try XCTUnwrap(DaySiteSplit.make(day([
            siteShift(here, time(7), time(11), breakMinutes: 15),
            siteShift(there, time(11), time(16), breakMinutes: 15)
        ])))
        XCTAssertNil(split.breakSiteID)
        XCTAssertEqual(split.segments, [.site(0, minutes: 240), .site(1, minutes: 300)], "no gap where none was")
    }

    func testOneSiteIsAnOrdinaryDay() {
        XCTAssertNil(DaySiteSplit.make(day([siteShift(here, time(7), time(16), breakMinutes: 30)])))
        XCTAssertNil(DaySiteSplit.make(day([Shift(start: time(7), end: time(12)), siteShift(here, time(13), time(16))])))
        XCTAssertNil(DaySiteSplit.make(day([])))
    }

    func testHoursOfYourOwnBesideTwoSitesKeepTheirRow() throws {
        let split = try XCTUnwrap(DaySiteSplit.make(day([
            siteShift(here, time(7), time(11)),
            siteShift(there, time(12), time(15)),
            Shift(start: time(17), end: time(18))
        ])))
        XCTAssertEqual(split.parts.map(\.siteID), [here, there, nil])
    }

    func testANightShiftIsNotDrawnAsABar() throws {
        let split = try XCTUnwrap(DaySiteSplit.make(day([
            siteShift(here, time(18), time(23)),
            siteShift(there, time(23, 30), time(2))
        ])))
        XCTAssertEqual(split.segments, [], "past midnight there is no one line to draw")
        XCTAssertEqual(split.parts.count, 2)
    }
}
