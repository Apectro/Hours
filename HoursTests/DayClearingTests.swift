import XCTest
@testable import Hours

/// Clearing a day, from the editor's "Clear this day" or a swipe on the
/// calendar's week list (1.3): everything typed in for the day goes, and the
/// hours written on a site stay, since they belong to the site's day.
final class DayClearingTests: XCTestCase {
    private let date = Fixture.date(2026, 11, 4)
    private let site = UUID()

    func testNothingStoredLeavesNothingToDo() {
        XCTAssertEqual(DayClearing.plan(for: nil), .nothing)
    }

    func testADayOfYourOwnIsDeleted() {
        let record = DayRecord(date: date, start: Fixture.time(7), end: Fixture.time(15), note: "Rain")
        XCTAssertEqual(DayClearing.plan(for: record), .delete(date))
    }

    func testADayOfLeaveIsDeleted() {
        XCTAssertEqual(DayClearing.plan(for: DayRecord(date: date, dayTypeID: .vacation)), .delete(date))
    }

    func testSiteHoursStayAndEverythingElseGoes() {
        var siteShift = Shift(start: Fixture.time(7), end: Fixture.time(16))
        siteShift.siteID = site
        let own = Shift(start: Fixture.time(17), end: Fixture.time(19))
        var record = DayRecord(date: date, shifts: [own, siteShift])
        record.note = "Overtime at home"
        record.kilometres = 40
        guard case let .keep(kept) = DayClearing.plan(for: record) else {
            return XCTFail("site hours should be kept")
        }
        XCTAssertEqual(kept.date, date)
        XCTAssertEqual(kept.shifts, [siteShift])
        XCTAssertEqual(kept.note, "")
        XCTAssertEqual(kept.kilometres, 0)
        XCTAssertNil(kept.dayTypeID)
    }

    func testADayWithOnlySiteHoursHasNothingOfYoursToClear() {
        var siteShift = Shift(start: Fixture.time(7), end: Fixture.time(16))
        siteShift.siteID = site
        XCTAssertEqual(DayClearing.plan(for: DayRecord(date: date, shifts: [siteShift])), .nothing)
    }
}
