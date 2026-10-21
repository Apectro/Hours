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

    // MARK: - Paid breaks

    private func calculator(primaryPaid: Bool, sitePaid: Bool) -> SiteDayCalculator {
        var settings = Fixture.settings()
        settings.jobs = [
            Job(id: Job.primaryID, name: "Main", breaksArePaid: primaryPaid, sortOrder: 0),
            Job(id: siteJobID, name: "Builder", breaksArePaid: sitePaid, sortOrder: 1)
        ]
        return SiteDayCalculator(settings: settings, calendar: Fixture.calendar())
    }

    private let siteJobID = UUID(uuidString: "00000000-0000-4000-8000-0000000000CC")!

    func testAPaidBreakJobCountsTheBreakForEveryone() {
        var siteDay = day(present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: UUID())])
        siteDay.jobID = siteJobID
        let result = calculator(primaryPaid: false, sitePaid: true).compute(siteDay)

        XCTAssertEqual(result.people.map(\.workedMinutes), [540, 540], "07:00–16:00 is nine hours")
        XCTAssertEqual(result.people.map(\.breakMinutes), [30, 30], "the break is still on the sheet")
        XCTAssertEqual(result.crewTotalMinutes, 1080)
    }

    func testAPaidBreakJobAppliesToExceptionsToo() {
        let early = UUID()
        let longBreak = UUID()
        var siteDay = day(present: [
            Attendance(memberID: early, end: Fixture.time(13)),
            Attendance(memberID: longBreak, breakMinutes: 60)
        ])
        siteDay.jobID = siteJobID
        let result = calculator(primaryPaid: false, sitePaid: true).compute(siteDay)

        XCTAssertEqual(result.people.first { $0.memberID == early }?.workedMinutes, 360)
        XCTAssertEqual(result.people.first { $0.memberID == longBreak }?.workedMinutes, 540)
        XCTAssertEqual(result.people.first { $0.memberID == longBreak }?.breakMinutes, 60)
    }

    func testAnUnpaidSiteJobStillSubtractsTheBreak() {
        var siteDay = day(present: [Attendance(memberID: UUID())])
        siteDay.jobID = siteJobID
        let result = calculator(primaryPaid: true, sitePaid: false).compute(siteDay)

        XCTAssertEqual(result.people.first?.workedMinutes, 510)
    }

    /// A day freezes its site's job when it is written, so no job on the day
    /// means the site had none, and its hours count towards the primary job.
    func testASiteWithoutAJobFollowsThePrimaryJob() {
        let siteDay = day(present: [Attendance(memberID: UUID())])

        XCTAssertEqual(calculator(primaryPaid: true, sitePaid: false).compute(siteDay).people.first?.workedMinutes, 540)
        XCTAssertEqual(calculator(primaryPaid: false, sitePaid: true).compute(siteDay).people.first?.workedMinutes, 510)
    }

    /// Your row on the site and your own calendar day are worked out from the
    /// same job, so they cannot disagree.
    func testYourSiteRowAgreesWithYourCalendar() {
        var siteDay = day(present: [Attendance(memberID: CrewMember.youID)])
        siteDay.jobID = siteJobID
        var settings = Fixture.settings()
        settings.jobs = [
            Job(id: Job.primaryID, name: "Main", sortOrder: 0),
            Job(id: siteJobID, name: "Builder", breaksArePaid: true, sortOrder: 1)
        ]

        let site = SiteDayCalculator(settings: settings, calendar: Fixture.calendar()).compute(siteDay)
        let record = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay], on: date)
        let calendarDay = Fixture.calculator(settings: settings).compute(record: record, on: date)

        XCTAssertEqual(site.people.first?.workedMinutes, 540)
        XCTAssertEqual(calendarDay.workedMinutes, 540)
    }

    func testYouComeFirst() {
        let other = UUID()
        let result = calculator().compute(
            day(present: [Attendance(memberID: other), Attendance(memberID: CrewMember.youID)])
        )
        XCTAssertEqual(result.people.map(\.memberID), [CrewMember.youID, other])
    }
}
