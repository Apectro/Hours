import XCTest
@testable import Hours

final class SiteDayCalculatorTests: XCTestCase {
    private let siteID = UUID()
    private let date = Fixture.workingTuesday

    private func calculator(rounding: RoundingRule = .exact) -> SiteDayCalculator {
        SiteDayCalculator(settings: Fixture.settings(rounding: rounding), calendar: Fixture.calendar())
    }

    private func day(
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(16),
        breakMinutes: Int = 30,
        present: [Attendance]
    ) -> SiteDay {
        SiteDay(siteID: siteID, date: date, start: start, end: end, breakMinutes: breakMinutes, present: present)
    }

    func testEveryoneGetsSiteTimes() {
        let members = [UUID(), UUID(), CrewMember.youID]
        let result = calculator().compute(day(present: members.map { Attendance(memberID: $0) }))

        XCTAssertEqual(result.people.count, 3)
        XCTAssertTrue(result.people.allSatisfy { $0.workedMinutes == 510 && !$0.isException })
        XCTAssertEqual(result.crewTotalMinutes, 1530)
        XCTAssertEqual(result.people.first?.memberID, CrewMember.youID)
    }

    func testLeftEarlyOverridesOnlyThatPerson() {
        let early = UUID()
        let others = [UUID(), UUID()]
        let present = [Attendance(memberID: others[0]), Attendance(memberID: early, end: Fixture.time(13)), Attendance(memberID: others[1])]
        let result = calculator().compute(day(present: present))

        let earlyDay = result.people.first { $0.memberID == early }
        XCTAssertEqual(earlyDay?.workedMinutes, 330)
        XCTAssertEqual(earlyDay?.isException, true)
        XCTAssertEqual(earlyDay?.start, Fixture.time(7))
        XCTAssertEqual(earlyDay?.end, Fixture.time(13))
        XCTAssertEqual(result.people.filter { $0.memberID != early }.map(\.workedMinutes), [510, 510])
        XCTAssertEqual(result.people.filter { $0.memberID != early }.map(\.isException), [false, false])
    }

    func testNotTickedGetsNothing() {
        let present = UUID()
        let absent = UUID()
        let result = calculator().compute(day(present: [Attendance(memberID: present)]))

        XCTAssertEqual(result.people.map(\.memberID), [present])
        XCTAssertFalse(result.people.contains { $0.memberID == absent })
        XCTAssertEqual(result.crewTotalMinutes, 510)
    }

    func testOvernightSiteDay() {
        let result = calculator().compute(
            day(start: Fixture.time(22), end: Fixture.time(6), present: [Attendance(memberID: UUID())])
        )
        XCTAssertEqual(result.people.first?.workedMinutes, 450)
    }

    func testBreakOverrideApplies() {
        let result = calculator().compute(day(present: [Attendance(memberID: UUID(), breakMinutes: 60)]))
        XCTAssertEqual(result.people.first?.workedMinutes, 480)
        XCTAssertEqual(result.people.first?.breakMinutes, 60)
        XCTAssertEqual(result.people.first?.isException, true)
    }

    func testZeroLengthOverrideIsZeroWithWarning() {
        let result = calculator().compute(
            day(present: [Attendance(memberID: UUID(), start: Fixture.time(9), end: Fixture.time(9))])
        )
        XCTAssertEqual(result.people.first?.workedMinutes, 0)
        XCTAssertEqual(result.people.first?.warnings, [.zeroLengthShift])
    }

    func testBreakLongerThanSpanIsZeroWithWarning() {
        let result = calculator().compute(
            day(start: Fixture.time(7), end: Fixture.time(8), breakMinutes: 90, present: [Attendance(memberID: UUID())])
        )
        XCTAssertEqual(result.people.first?.workedMinutes, 0)
        XCTAssertEqual(result.people.first?.warnings, [.breakLongerThanShift])
    }

    func testMissingTimesCountNothing() {
        let result = calculator().compute(day(start: nil, end: nil, present: [Attendance(memberID: UUID())]))
        XCTAssertEqual(result.people.first?.workedMinutes, 0)
        XCTAssertNil(result.people.first?.start)
    }

    func testQuarterHourRoundingAppliesPerPerson() {
        // 07:00-15:50 less 30 = 500 -> 500 rounds to 495 (nearest quarter); 07:00-16:00 = 510 -> 510.
        let a = UUID()
        let b = UUID()
        let present = [Attendance(memberID: a, end: Fixture.time(15, 50)), Attendance(memberID: b)]
        let result = calculator(rounding: .nearestQuarterHour).compute(day(present: present))

        XCTAssertEqual(result.people.first { $0.memberID == a }?.workedMinutes, 495)
        XCTAssertEqual(result.people.first { $0.memberID == b }?.workedMinutes, 510)
        XCTAssertEqual(result.crewTotalMinutes, 1005)
    }

    func testYouComeFirst() {
        let other = UUID()
        let result = calculator().compute(
            day(present: [Attendance(memberID: other), Attendance(memberID: CrewMember.youID)])
        )
        XCTAssertEqual(result.people.map(\.memberID), [CrewMember.youID, other])
    }
}
