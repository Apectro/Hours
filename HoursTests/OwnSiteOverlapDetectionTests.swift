import XCTest
@testable import Hours

/// The day editor's warning before saving (2026-11-24): which of your own
/// blocks run into a site's times, and which site. What the engine does
/// with such hours is `OwnAndSiteHoursOverlapTests`: they count once.
final class OwnSiteOverlapDetectionTests: XCTestCase {
    private let here = UUID()
    private let there = UUID()

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func site(_ id: UUID, _ start: TimeOfDay?, _ end: TimeOfDay?) -> Shift {
        Shift(id: id, start: start, end: end, siteID: id)
    }

    func testABlockRunningIntoASiteIsNamedWithBothTimes() {
        let found = OwnSiteOverlap.find(in: [
            site(here, time(7), time(12)),
            Shift(start: time(11, 30), end: time(12, 30))
        ])
        XCTAssertEqual(found, [OwnSiteOverlap(
            ownStart: time(11, 30), ownEnd: time(12, 30),
            siteID: here, siteStart: time(7), siteEnd: time(12),
            sharedMinutes: 30
        )])
    }

    func testBlocksThatOnlyTouchDoNotOverlap() {
        XCTAssertTrue(OwnSiteOverlap.find(in: [
            site(here, time(7), time(12)),
            Shift(start: time(12), end: time(13)),
            Shift(start: time(6), end: time(7))
        ]).isEmpty)
    }

    func testSeparateBlocksDoNotOverlap() {
        XCTAssertTrue(OwnSiteOverlap.find(in: [
            site(here, time(7), time(15)),
            Shift(start: time(16), end: time(17, 30))
        ]).isEmpty)
    }

    func testOneBlockAcrossTwoSitesIsOneEntryEachInTimeOrder() {
        let found = OwnSiteOverlap.find(in: [
            site(there, time(12, 30), time(15, 30)),
            site(here, time(7), time(12)),
            Shift(start: time(11), end: time(13))
        ])
        XCTAssertEqual(found.map(\.siteID), [here, there])
        XCTAssertEqual(found.map(\.sharedMinutes), [60, 30])
    }

    func testTwoSitesAreNeverAnOverlapOfYourOwn() {
        XCTAssertTrue(OwnSiteOverlap.find(in: [
            site(here, time(7), time(12)),
            site(there, time(11), time(15))
        ]).isEmpty)
    }

    func testHalfTypedAndOvernightBlocksAreLeftAlone() {
        XCTAssertTrue(OwnSiteOverlap.find(in: [
            site(here, time(7), time(12)),
            Shift(start: time(8), end: nil),
            Shift(start: time(22), end: time(8))
        ]).isEmpty, "as the calculator, which takes nothing off a block past midnight")
        XCTAssertTrue(OwnSiteOverlap.find(in: [
            site(here, time(7), nil),
            Shift(start: time(8), end: time(9))
        ]).isEmpty, "a site day with no end has no times to run into")
    }

    func testNoSiteNoWarning() {
        XCTAssertTrue(OwnSiteOverlap.find(in: [Shift(start: time(8), end: time(16))]).isEmpty)
        XCTAssertTrue(OwnSiteOverlap.find(in: []).isEmpty)
    }

    /// The warning and the arithmetic are about the same minutes: what is
    /// reported as shared is what the day does not count twice.
    func testWhatIsReportedIsWhatTheDayCountsOnce() {
        let shifts = [
            site(here, time(7), time(12)),
            Shift(start: time(11, 30), end: time(12, 30))
        ]
        let record = DayRecord(date: Fixture.workingMonday, shifts: shifts)
        let day = Fixture.calculator().compute(record: record, on: record.date)
        let shared = OwnSiteOverlap.find(in: shifts).reduce(0) { $0 + $1.sharedMinutes }
        XCTAssertEqual(day.workedMinutes, 300 + 60 - shared)
        XCTAssertTrue(day.warnings.contains(.ownHoursOverlapSite))
    }
}
