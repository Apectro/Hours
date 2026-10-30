import XCTest
@testable import Hours

/// The crew's day (1.2 redesign, mockups 06 and 07): how each person reads
/// on "Who's different today?", the site's usual day in one tap, "Same as
/// the day before", the late/early explanation and the crew figures the
/// sheets show.
final class SiteCrewDayTests: XCTestCase {
    private let siteID = UUID()
    private let otherSiteID = UUID()
    private let date = Fixture.workingTuesday
    private let ivan = UUID()
    private let marko = UUID()

    private var calculator: SiteDayCalculator {
        SiteDayCalculator(settings: Fixture.settings(), calendar: Fixture.calendar())
    }

    private func day(present: [Attendance], absences: [CrewAbsence] = []) -> SiteDay {
        SiteDay(
            siteID: siteID, date: date,
            start: Fixture.time(7), end: Fixture.time(16), breakMinutes: 30,
            present: present, absences: absences
        )
    }

    // MARK: - States

    func testStatesOfEachKindOfPerson() {
        let sick = UUID()
        let gone = UUID()
        let base = day(
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan, end: Fixture.time(13))],
            absences: [CrewAbsence(memberID: sick, dayTypeID: .sick)]
        )
        XCTAssertEqual(SiteCrewState.of(CrewMember.youID, in: base), .usual)
        XCTAssertEqual(SiteCrewState.of(ivan, in: base), .ownTimes)
        XCTAssertEqual(SiteCrewState.of(sick, in: base), .away(.dayType(.sick)))
        XCTAssertEqual(SiteCrewState.of(gone, in: base), .notHere)
    }

    func testSomeoneWhoMovedReadsAsMoved() {
        var base = day(present: [Attendance(memberID: ivan, end: Fixture.time(12, 40))])
        base.moves = [SiteMove(
            toSiteID: otherSiteID, left: Fixture.time(12, 40), started: Fixture.time(12, 40),
            breakPlacement: .there,
            people: [SiteMove.Person(memberID: ivan, targetMemberID: ivan, before: Attendance(memberID: ivan))],
            createdTargetDay: true
        )]
        XCTAssertEqual(SiteCrewState.of(ivan, in: base), .moved(otherSiteID))
        XCTAssertTrue(SiteCrewState.of(ivan, in: base).isHere)
        XCTAssertFalse(SiteCrewState.of(ivan, in: base).needsAttention)
    }

    func testAttentionIsLateEarlyAndAway() {
        XCTAssertTrue(SiteCrewState.ownTimes.needsAttention)
        XCTAssertTrue(SiteCrewState.away(.dayType(.sick)).needsAttention)
        XCTAssertFalse(SiteCrewState.usual.needsAttention)
        XCTAssertFalse(SiteCrewState.notHere.needsAttention)
        XCTAssertFalse(SiteCrewState.notHere.isHere)
    }

    // MARK: - Changing one person

    func testUsualTicksInAtTheSiteTimesAndClearsTheReason() {
        let base = day(
            present: [Attendance(memberID: ivan, start: Fixture.time(9))],
            absences: [CrewAbsence(memberID: marko, dayTypeID: .sick)]
        )
        let ivanUsual = base.settingUsual(for: ivan, allowanceByDefault: false)
        XCTAssertEqual(ivanUsual.attendance(for: ivan), Attendance(memberID: ivan))

        let markoUsual = base.settingUsual(for: marko, allowanceByDefault: true)
        XCTAssertEqual(markoUsual.attendance(for: marko), Attendance(memberID: marko))
        XCTAssertNil(markoUsual.absenceReason(for: marko))
        XCTAssertTrue(markoUsual.hasAllowance(for: marko))
    }

    func testUsualKeepsTheAllowanceOfSomeoneAlreadyHere() {
        var base = day(present: [Attendance(memberID: ivan, end: Fixture.time(13))])
        base.allowanceMemberIDs = [ivan]
        let usual = base.settingUsual(for: ivan, allowanceByDefault: false)
        XCTAssertTrue(usual.hasAllowance(for: ivan))
    }

    func testNotHereUnticksAndGivesNoReason() {
        let base = day(
            present: [Attendance(memberID: ivan)],
            absences: [CrewAbsence(memberID: marko, dayTypeID: .sick)]
        )
        let ivanGone = base.settingNotHere(for: ivan)
        XCTAssertNil(ivanGone.attendance(for: ivan))
        XCTAssertEqual(SiteCrewState.of(ivan, in: ivanGone), .notHere)
        XCTAssertEqual(SiteCrewState.of(marko, in: base.settingNotHere(for: marko)), .notHere)
    }

    func testOwnTimesTicksSomeoneInWithThem() {
        let base = day(present: [], absences: [CrewAbsence(memberID: ivan, dayTypeID: .sick)])
        let late = base.settingAttendance(Attendance(memberID: ivan, start: Fixture.time(9)), allowanceByDefault: false)
        XCTAssertEqual(late.attendance(for: ivan)?.start, Fixture.time(9))
        XCTAssertNil(late.absenceReason(for: ivan))
        XCTAssertEqual(SiteCrewState.of(ivan, in: late), .ownTimes)
    }

    // MARK: - The usual day

    func testUsualDayIsTheSetupsTimesForTheDefaultCrew() {
        let setup = SiteSetup(start: Fixture.time(7), end: Fixture.time(16), breakMinutes: 30)
        let usual = SiteDay.usual(
            siteID: siteID, date: date, jobID: nil,
            times: SiteUsualTimes(setup: setup, schedule: WorkSchedule()),
            crew: [CrewMember.youID, ivan, marko],
            allowanceByDefault: false
        )
        XCTAssertEqual(usual.start, Fixture.time(7))
        XCTAssertEqual(usual.end, Fixture.time(16))
        XCTAssertEqual(usual.breakMinutes, 30)
        XCTAssertEqual(usual.present.map(\.memberID), [CrewMember.youID, ivan, marko])
        XCTAssertTrue(usual.present.allSatisfy { SiteCrewState.of($0.memberID, in: usual) == .usual })
        XCTAssertTrue(usual.allowanceMemberIDs.isEmpty)
        XCTAssertEqual(calculator.compute(usual).crewTotalMinutes, 3 * 510)
    }

    func testUsualTimesFallBackToTheWorkingWeek() {
        var schedule = WorkSchedule()
        schedule.defaultStart = Fixture.time(6)
        schedule.defaultEnd = Fixture.time(14, 30)
        schedule.defaultBreakMinutes = 45
        let times = SiteUsualTimes(setup: SiteSetup(), schedule: schedule)
        XCTAssertEqual(times, SiteUsualTimes(start: Fixture.time(6), end: Fixture.time(14, 30), breakMinutes: 45))
    }

    func testUsualDayGivesTheAllowanceWhenTheSiteDoes() {
        let usual = SiteDay.usual(
            siteID: siteID, date: date, jobID: nil,
            times: SiteUsualTimes(start: Fixture.time(7), end: Fixture.time(16), breakMinutes: 0),
            crew: [CrewMember.youID, ivan],
            allowanceByDefault: true
        )
        XCTAssertEqual(usual.allowanceCount, 2)
    }

    // MARK: - Same as the day before

    func testCopyTakesTimesCrewAllowanceAndKilometresButNoExceptions() {
        var last = day(
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan, end: Fixture.time(12)), Attendance(memberID: marko)],
            absences: [CrewAbsence(memberID: UUID(), dayTypeID: .sick)]
        )
        last.allowanceMemberIDs = [ivan]
        last.kilometres = 42
        last.note = "Crane delivery"
        last.isBadWeatherStop = true
        let next = Fixture.date(2026, 8, 5)
        let jobID = UUID()

        let copy = last.copied(to: next, leavingOut: [marko], jobID: jobID)

        XCTAssertEqual(copy.date, next)
        XCTAssertEqual(copy.siteID, siteID)
        XCTAssertEqual(copy.start, Fixture.time(7))
        XCTAssertEqual(copy.end, Fixture.time(16))
        XCTAssertEqual(copy.breakMinutes, 30)
        XCTAssertEqual(copy.present, [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan)])
        XCTAssertEqual(copy.allowanceMemberIDs, [ivan])
        XCTAssertEqual(copy.kilometres, 42)
        XCTAssertEqual(copy.jobID, jobID)
        XCTAssertEqual(copy.note, "")
        XCTAssertTrue(copy.absences.isEmpty)
        XCTAssertFalse(copy.isBadWeatherStop)
        XCTAssertTrue(copy.moves.isEmpty)
    }

    // MARK: - Late or early

    func testLeftEarlyIsMinutesBeforeTheSiteEnd() {
        let base = day(present: [])
        let difference = SiteTimeDifference.of(Attendance(memberID: ivan, end: Fixture.time(13)), in: base)
        XCTAssertEqual(difference.startMinutes, 0)
        XCTAssertEqual(difference.endMinutes, -180)
        XCTAssertEqual(difference.breakMinutes, 0)
        XCTAssertFalse(difference.isNone)
    }

    func testCameLateAndAccrossMidnight() {
        let base = day(present: [])
        XCTAssertEqual(SiteTimeDifference.of(Attendance(memberID: ivan, start: Fixture.time(8, 30)), in: base).startMinutes, 90)

        let night = SiteDay(siteID: siteID, date: date, start: Fixture.time(22), end: Fixture.time(6), present: [])
        let stayed = SiteTimeDifference.of(Attendance(memberID: ivan, end: Fixture.time(7)), in: night)
        XCTAssertEqual(stayed.endMinutes, 60)
        let early = SiteTimeDifference.of(Attendance(memberID: ivan, start: Fixture.time(21)), in: night)
        XCTAssertEqual(early.startMinutes, -60)
    }

    func testOwnBreakAndNoDifference() {
        let base = day(present: [])
        XCTAssertEqual(SiteTimeDifference.of(Attendance(memberID: ivan, breakMinutes: 60), in: base).breakMinutes, 30)
        XCTAssertTrue(SiteTimeDifference.of(Attendance(memberID: ivan), in: base).isNone)
        // A site day with no times has nothing to differ from.
        let untimed = SiteDay(siteID: siteID, date: date, present: [])
        XCTAssertTrue(SiteTimeDifference.of(Attendance(memberID: ivan, end: Fixture.time(13)), in: untimed).isNone)
    }

    // MARK: - Figures

    func testFiguresSayEachWhenEveryoneIsTheSame() {
        let result = calculator.compute(day(present: [Attendance(memberID: ivan), Attendance(memberID: marko)]))
        let figures = SiteCrewFigures(result.people)
        XCTAssertEqual(figures.people, 2)
        XCTAssertEqual(figures.totalMinutes, 1020)
        XCTAssertEqual(figures.eachMinutes, 510)
    }

    func testFiguresHaveNoEachWhenHoursDiffer() {
        let result = calculator.compute(day(present: [Attendance(memberID: ivan), Attendance(memberID: marko, end: Fixture.time(13))]))
        let figures = SiteCrewFigures(result.people)
        XCTAssertEqual(figures.people, 2)
        XCTAssertNil(figures.eachMinutes)
        XCTAssertEqual(SiteCrewFigures([]).eachMinutes, nil)
        XCTAssertEqual(SiteCrewFigures([]).people, 0)
    }

    func testWeatherStopPreviewCountsTheHoursUntilTheStop() {
        let base = day(present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan)])
        let stopped = SiteCrewFigures.ifStopped(base, at: Fixture.time(11), startingAt: Fixture.time(8), calculator: calculator)
        XCTAssertEqual(stopped.people, 2)
        // 07:00–11:00 less the 30-minute break.
        XCTAssertEqual(stopped.eachMinutes, 210)

        let none = SiteCrewFigures.ifStopped(base, at: nil, startingAt: Fixture.time(8), calculator: calculator)
        XCTAssertEqual(none.people, 2)
        XCTAssertEqual(none.totalMinutes, 0)

        // A day with no times yet starts at the given start.
        let untimed = SiteDay(siteID: siteID, date: date, present: [Attendance(memberID: ivan)])
        let fromStart = SiteCrewFigures.ifStopped(untimed, at: Fixture.time(11), startingAt: Fixture.time(8), calculator: calculator)
        XCTAssertEqual(fromStart.eachMinutes, 180)
    }

    func testMoveFiguresSplitTheDay() throws {
        let source = day(present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan), Attendance(memberID: marko)])
        let target = Site(id: otherSiteID, name: "Jarunski")
        let outcome = try SiteMoving.apply(SiteMoveRequest(
            source: source, target: nil, targetSite: target,
            sourceCrew: [CrewMember(id: ivan, siteID: siteID, name: "Ivan", sortOrder: 0),
                         CrewMember(id: marko, siteID: siteID, name: "Marko", sortOrder: 1)],
            targetCrew: [],
            memberIDs: [CrewMember.youID, ivan],
            left: Fixture.time(12, 40), started: Fixture.time(12, 40),
            breakPlacement: .there, lock: .unlocked, tracksAllowance: false
        ))
        let figures = SiteCrewFigures.ofMove(outcome, calculator: calculator)
        XCTAssertEqual(figures.here.people, 2)
        XCTAssertEqual(figures.here.eachMinutes, 340)
        XCTAssertEqual(figures.there.people, 2)
        XCTAssertEqual(figures.there.eachMinutes, 170)
    }
}
