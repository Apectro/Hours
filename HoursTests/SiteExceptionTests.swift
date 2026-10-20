import XCTest
@testable import Hours

final class SiteExceptionTests: XCTestCase {
    private let member = UUID()

    private func day(
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(15, 30),
        _ attendance: Attendance
    ) -> SiteDay {
        SiteDay(siteID: UUID(), date: Fixture.workingTuesday, start: start, end: end, breakMinutes: 30, present: [attendance])
    }

    func testSiteTimesAreNoException() {
        XCTAssertNil(SiteException.of(member, in: day(Attendance(memberID: member))))
    }

    func testNotPresentIsNoException() {
        XCTAssertNil(SiteException.of(UUID(), in: day(Attendance(memberID: member, end: Fixture.time(12)))))
    }

    func testEarlierEndIsLeavingEarly() {
        let result = SiteException.of(member, in: day(Attendance(memberID: member, end: Fixture.time(12))))
        XCTAssertEqual(result, .leftEarly)
    }

    func testLaterStartIsComingLate() {
        let result = SiteException.of(member, in: day(Attendance(memberID: member, start: Fixture.time(9))))
        XCTAssertEqual(result, .cameLate)
    }

    func testStayingLateIsOnlyChangedTimes() {
        let result = SiteException.of(member, in: day(Attendance(memberID: member, end: Fixture.time(18))))
        XCTAssertEqual(result, .changedTimes)
    }

    func testBothEndsOrBreakAreChangedTimes() {
        XCTAssertEqual(
            SiteException.of(member, in: day(Attendance(memberID: member, start: Fixture.time(8), end: Fixture.time(12)))),
            .changedTimes
        )
        XCTAssertEqual(
            SiteException.of(member, in: day(Attendance(memberID: member, breakMinutes: 60))),
            .changedTimes
        )
    }

    /// An overnight site day: 22:00 to 06:00. Leaving at 02:00 is early even
    /// though 02:00 is a smaller number than 22:00.
    func testOvernightLeavingEarly() {
        let result = SiteException.of(
            member,
            in: day(start: Fixture.time(22), end: Fixture.time(6), Attendance(memberID: member, end: Fixture.time(2)))
        )
        XCTAssertEqual(result, .leftEarly)
    }

    func testNoSiteTimesIsOnlyChangedTimes() {
        let result = SiteException.of(member, in: day(start: nil, end: nil, Attendance(memberID: member, end: Fixture.time(12))))
        XCTAssertEqual(result, .changedTimes)
    }
}
