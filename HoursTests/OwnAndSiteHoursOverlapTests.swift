import XCTest
@testable import Hours

/// Hours of your own (a running clock, or a block you typed) and site hours
/// for the same stretch of time are the same work, so they count once.
final class OwnAndSiteHoursOverlapTests: XCTestCase {
    private let site = UUID()

    private func record(own: Shift?, site siteShift: Shift?) -> DayRecord {
        var record = DayRecord(date: Fixture.workingMonday)
        record.shifts = [own, siteShift].compactMap { $0 }
        return record
    }

    private func ownShift(_ start: TimeOfDay, _ end: TimeOfDay, break minutes: Int = 0) -> Shift {
        Shift(start: start, end: end, breaks: minutes > 0 ? [.duration(minutes)] : [])
    }

    private func siteShift(_ start: TimeOfDay, _ end: TimeOfDay, break minutes: Int = 0) -> Shift {
        Shift(id: site, start: start, end: end, breaks: minutes > 0 ? [.duration(minutes)] : [], siteID: site)
    }

    func testTheSameHoursFromTheClockAndTheSiteCountOnce() {
        let day = record(
            own: ownShift(Fixture.time(7), Fixture.time(15, 30), break: 30),
            site: siteShift(Fixture.time(7), Fixture.time(15, 30), break: 30)
        )
        let result = Fixture.calculator().compute(record: day, on: Fixture.workingMonday)
        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertTrue(result.warnings.contains(.ownHoursOverlapSite))
    }

    func testOwnTimeOutsideTheSiteStillCounts() {
        // Clocked in at 06:00 before the site day started at 07:00.
        let day = record(
            own: ownShift(Fixture.time(6), Fixture.time(15, 30)),
            site: siteShift(Fixture.time(7), Fixture.time(15, 30), break: 30)
        )
        let result = Fixture.calculator().compute(record: day, on: Fixture.workingMonday)
        XCTAssertEqual(result.workedMinutes, 60 + 480)
    }

    func testSeparateBlocksAreUntouched() {
        let day = record(
            own: ownShift(Fixture.time(16), Fixture.time(18)),
            site: siteShift(Fixture.time(7), Fixture.time(15), break: 30)
        )
        let result = Fixture.calculator().compute(record: day, on: Fixture.workingMonday)
        XCTAssertEqual(result.workedMinutes, 120 + 450)
        XCTAssertFalse(result.warnings.contains(.ownHoursOverlapSite))
    }

    func testTwoSitesAreNotTreatedAsOverlap() {
        var day = DayRecord(date: Fixture.workingMonday)
        let other = UUID()
        day.shifts = [
            siteShift(Fixture.time(7), Fixture.time(11, 30)),
            Shift(id: other, start: Fixture.time(12), end: Fixture.time(16), breaks: [.duration(30)], siteID: other),
        ]
        let result = Fixture.calculator().compute(record: day, on: Fixture.workingMonday)
        XCTAssertEqual(result.workedMinutes, 270 + 210)
    }
}
