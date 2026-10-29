import XCTest
@testable import Hours

/// "Moved to another site…": part of the crew leaves one site in the middle
/// of the day and finishes it on another.
final class SiteMoveTests: XCTestCase {
    private let date = Fixture.workingTuesday
    private let here = Site(name: "Hauptstraße 12", jobID: UUID())
    private let there = Site(name: "Trg Pravde", jobID: UUID())

    private lazy var ivan = CrewMember(siteID: here.id, name: "Ivan", sortOrder: 0)
    private lazy var marko = CrewMember(siteID: here.id, name: "Marko", sortOrder: 1)
    private lazy var luka = CrewMember(siteID: here.id, name: "Luka", sortOrder: 2)
    private lazy var ana = CrewMember(siteID: here.id, name: "Ana", sortOrder: 3)
    /// The same people on the other site's own crew; Luka is not on it yet.
    private lazy var ivanThere = CrewMember(siteID: there.id, name: "ivan ", sortOrder: 0)
    private lazy var markoThere = CrewMember(siteID: there.id, name: "Marko", sortOrder: 4)

    private var hereCrew: [CrewMember] { [ivan, marko, luka, ana] }
    private var thereCrew: [CrewMember] { [ivanThere, markoThere] }

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    /// 7:00–16:00 with half an hour's break, you and four coworkers.
    private func sourceDay() -> SiteDay {
        SiteDay(
            siteID: here.id,
            date: date,
            start: time(7),
            end: time(16),
            breakMinutes: 30,
            present: [CrewMember.youID, ivan.id, marko.id, luka.id, ana.id].map { Attendance(memberID: $0) },
            jobID: here.jobID
        )
    }

    private func request(
        source: SiteDay? = nil,
        target: SiteDay? = nil,
        who: [UUID]? = nil,
        left: TimeOfDay? = nil,
        started: TimeOfDay? = nil,
        placement: BreakPlacement = .there,
        lock: MonthLock = .unlocked,
        tracksAllowance: Bool = false,
        targetSite: Site? = nil
    ) -> SiteMoveRequest {
        SiteMoveRequest(
            source: source ?? sourceDay(),
            target: target,
            targetSite: targetSite ?? there,
            sourceCrew: hereCrew,
            targetCrew: thereCrew,
            memberIDs: who ?? [CrewMember.youID, ivan.id, marko.id, luka.id],
            left: left ?? time(11, 30),
            started: started ?? time(12),
            breakPlacement: placement,
            lock: lock,
            tracksAllowance: tracksAllowance
        )
    }

    private func worked(_ day: SiteDay, _ memberID: UUID) -> Int? {
        SiteDayCalculator(settings: Fixture.settings(), calendar: Fixture.calendar())
            .compute(day)
            .people
            .first { $0.memberID == memberID }?
            .workedMinutes
    }

    // MARK: - Applying

    func testTheFourWhoWentEndHereAtTheTimeTheyLeft() throws {
        let outcome = try SiteMoving.apply(request())

        for id in [CrewMember.youID, ivan.id, marko.id, luka.id] {
            let mine = outcome.source.resolved(for: id)
            XCTAssertEqual(mine?.start, time(7))
            XCTAssertEqual(mine?.end, time(11, 30))
            XCTAssertEqual(mine?.breakMinutes, 0, "the break went with them")
            XCTAssertEqual(worked(outcome.source, id), 270)
        }
    }

    func testWhoStaysIsUntouched() throws {
        let outcome = try SiteMoving.apply(request())

        XCTAssertEqual(outcome.source.attendance(for: ana.id), Attendance(memberID: ana.id))
        XCTAssertEqual(worked(outcome.source, ana.id), 510)
        XCTAssertEqual(outcome.source.start, time(7))
        XCTAssertEqual(outcome.source.end, time(16))
        XCTAssertEqual(outcome.source.breakMinutes, 30)
    }

    func testTheOtherSiteGetsANewDayWithItsOwnJob() throws {
        let outcome = try SiteMoving.apply(request())
        let target = outcome.target

        XCTAssertEqual(target.siteID, there.id)
        XCTAssertEqual(target.date, date)
        XCTAssertEqual(target.jobID, there.jobID, "a new day freezes its own site's job")
        XCTAssertEqual(target.start, time(12))
        XCTAssertEqual(target.end, time(16))
        XCTAssertEqual(target.breakMinutes, 30)
        XCTAssertTrue(outcome.move.createdTargetDay)
        XCTAssertEqual(target.present.count, 4)
        for attendance in target.present {
            XCTAssertFalse(target.hasException(attendance.memberID), "everyone works the new day's own times")
            XCTAssertEqual(worked(target, attendance.memberID), 210)
        }
    }

    func testPeopleAreMatchedToTheOtherCrewByName() throws {
        let outcome = try SiteMoving.apply(request())
        let ids = Set(outcome.target.present.map(\.memberID))

        XCTAssertTrue(ids.contains(CrewMember.youID))
        XCTAssertTrue(ids.contains(ivanThere.id), "\"ivan \" there is Ivan here")
        XCTAssertTrue(ids.contains(markoThere.id))
        XCTAssertFalse(ids.contains(ivan.id), "a site keeps its own crew")
    }

    func testSomeoneNotOnTheOtherCrewIsAddedToIt() throws {
        let outcome = try SiteMoving.apply(request())

        XCTAssertEqual(outcome.crewChanges.count, 1)
        let added = try XCTUnwrap(outcome.crewChanges.first)
        XCTAssertEqual(added.name, "Luka")
        XCTAssertEqual(added.siteID, there.id)
        XCTAssertFalse(added.isHidden)
        XCTAssertEqual(added.sortOrder, 5, "after the crew already there")
        XCTAssertTrue(outcome.target.present.contains { $0.memberID == added.id })
    }

    func testSomeoneHiddenOnTheOtherCrewIsShownAgainRatherThanAddedTwice() throws {
        var hidden = CrewMember(siteID: there.id, name: "Luka", isHidden: true, sortOrder: 2)
        var request = request()
        request.targetCrew = thereCrew + [hidden]

        let outcome = try SiteMoving.apply(request)

        hidden.isHidden = false
        XCTAssertEqual(outcome.crewChanges, [hidden])
        XCTAssertTrue(outcome.target.present.contains { $0.memberID == hidden.id })
    }

    func testOnePersonCanMoveAlone() throws {
        let outcome = try SiteMoving.apply(request(who: [ivan.id]))

        XCTAssertEqual(outcome.source.resolved(for: ivan.id)?.end, time(11, 30))
        XCTAssertEqual(outcome.source.resolved(for: CrewMember.youID)?.end, time(16))
        XCTAssertEqual(outcome.target.present.map(\.memberID), [ivanThere.id])
        XCTAssertEqual(outcome.move.people.count, 1)
    }

    func testTheMoveIsRecordedOnTheDayTheyLeft() throws {
        let outcome = try SiteMoving.apply(request(), moveID: UUID(uuidString: "00000000-0000-4000-8000-00000000AB01")!)

        XCTAssertEqual(outcome.source.moves, [outcome.move])
        XCTAssertEqual(outcome.move.toSiteID, there.id)
        XCTAssertEqual(outcome.move.left, time(11, 30))
        XCTAssertEqual(outcome.move.started, time(12))
        XCTAssertEqual(outcome.move.memberIDs, [CrewMember.youID, ivan.id, marko.id, luka.id])
        XCTAssertEqual(outcome.source.move(of: ivan.id), outcome.move)
        XCTAssertNil(outcome.source.move(of: ana.id))
        XCTAssertTrue(outcome.target.moves.isEmpty, "the record lives on one day only")
    }

    // MARK: - The break

    func testTheBreakCanStayHere() throws {
        let outcome = try SiteMoving.apply(request(placement: .here))

        XCTAssertEqual(outcome.source.resolved(for: ivan.id)?.breakMinutes, 30)
        XCTAssertNil(outcome.source.attendance(for: ivan.id)?.breakMinutes, "the site's own break, not an override")
        XCTAssertEqual(worked(outcome.source, ivan.id), 240)
        XCTAssertEqual(outcome.target.breakMinutes, 0)
        XCTAssertEqual(worked(outcome.target, ivanThere.id), 240)
    }

    func testTheBreakCanBeSplit() throws {
        let outcome = try SiteMoving.apply(request(placement: .split))

        XCTAssertEqual(outcome.source.resolved(for: ivan.id)?.breakMinutes, 15)
        XCTAssertEqual(outcome.target.breakMinutes, 15)
        XCTAssertEqual(worked(outcome.source, ivan.id)! + worked(outcome.target, ivanThere.id)!, 480)
    }

    func testAnOddBreakSplitsWithTheExtraMinuteHere() {
        XCTAssertEqual(SiteMoving.split(breakMinutes: 45, placement: .split).here, 23)
        XCTAssertEqual(SiteMoving.split(breakMinutes: 45, placement: .split).there, 22)
        XCTAssertEqual(SiteMoving.split(breakMinutes: 45, placement: .here).there, 0)
        XCTAssertEqual(SiteMoving.split(breakMinutes: 45, placement: .there).here, 0)
    }

    func testTheBreakGoesWhereItFallsInTime() {
        // An untimed break sits in the middle of the shift: 11:15–11:45.
        XCTAssertEqual(
            SiteMoving.defaultBreakPlacement(start: time(7), end: time(16), breakMinutes: 30, left: time(13)),
            .here,
            "taken before they left"
        )
        XCTAssertEqual(
            SiteMoving.defaultBreakPlacement(start: time(7), end: time(16), breakMinutes: 30, left: time(10)),
            .there
        )
        XCTAssertEqual(
            SiteMoving.defaultBreakPlacement(start: time(7), end: time(16), breakMinutes: 30, left: time(11, 30)),
            .there,
            "a break cut by the move goes to the other site"
        )
        XCTAssertEqual(
            SiteMoving.defaultBreakPlacement(start: nil, end: time(16), breakMinutes: 30, left: time(11)),
            .there
        )
    }

    // MARK: - An existing day on the other site

    func testAnExistingDayKeepsItsTimesItsJobAndItsPeople() throws {
        let someone = UUID()
        let existing = SiteDay(
            siteID: there.id,
            date: date,
            start: time(7),
            end: time(15),
            breakMinutes: 30,
            present: [Attendance(memberID: someone)],
            note: "Formwork",
            jobID: UUID(),
            absences: [CrewAbsence(memberID: UUID(), dayTypeID: .sick)]
        )

        let outcome = try SiteMoving.apply(request(target: existing))
        let target = outcome.target

        XCTAssertFalse(outcome.move.createdTargetDay)
        XCTAssertEqual(target.start, time(7))
        XCTAssertEqual(target.end, time(15))
        XCTAssertEqual(target.jobID, existing.jobID)
        XCTAssertEqual(target.note, "Formwork")
        XCTAssertEqual(target.absences, existing.absences, "absences are never moved")
        XCTAssertEqual(target.present.first, Attendance(memberID: someone))
        let ivanThere = try XCTUnwrap(target.resolved(for: self.ivanThere.id))
        XCTAssertEqual(ivanThere.start, time(12))
        XCTAssertEqual(ivanThere.end, time(16), "they work on to this day's original end")
        XCTAssertEqual(ivanThere.breakMinutes, 30)
    }

    func testAReasonGivenOnTheOtherSiteGoesWhenTheyArrive() throws {
        let existing = SiteDay(
            siteID: there.id,
            date: date,
            start: time(7),
            end: time(15),
            absences: [CrewAbsence(memberID: ivanThere.id, reason: .otherSite(here.id))]
        )

        let outcome = try SiteMoving.apply(request(target: existing, who: [ivan.id]))

        XCTAssertNil(outcome.target.absenceReason(for: ivanThere.id))
        XCTAssertNotNil(outcome.target.attendance(for: ivanThere.id))
    }

    func testAPersonsOwnEndIsTheEndTheyWorkOnTo() throws {
        var source = sourceDay()
        source.present[1] = Attendance(memberID: ivan.id, end: time(15))

        let outcome = try SiteMoving.apply(request(source: source, who: [ivan.id]))

        XCTAssertEqual(outcome.target.resolved(for: ivanThere.id)?.end, time(15))
    }

    func testTheAllowanceIsNotGivenTwiceForOneDay() throws {
        var source = sourceDay()
        source.allowanceMemberIDs = [ivan.id]
        var site = there
        site.allowanceByDefault = true

        let outcome = try SiteMoving.apply(request(source: source, who: [ivan.id, marko.id], tracksAllowance: true, targetSite: site))

        XCTAssertFalse(outcome.target.hasAllowance(for: ivanThere.id), "he has it here already")
        XCTAssertTrue(outcome.target.hasAllowance(for: markoThere.id))
    }

    // MARK: - Refusals

    func testAClosedMonthRefuses() {
        var lock = MonthLock()
        lock.lock(YearMonth(date))

        XCTAssertThrowsError(try SiteMoving.apply(request(lock: lock))) { error in
            XCTAssertTrue(error is MonthLock.Refusal)
        }
    }

    func testNobodyChosenIsRefused() {
        XCTAssertThrowsError(try SiteMoving.apply(request(who: []))) { error in
            XCTAssertEqual(error as? SiteMoveError, .nobody)
        }
    }

    func testTheSameSiteIsRefused() {
        XCTAssertThrowsError(try SiteMoving.apply(request(targetSite: here))) { error in
            XCTAssertEqual(error as? SiteMoveError, .sameSite)
        }
    }

    func testSomeoneAwayIsNeverMoved() {
        let source = sourceDay().settingAbsence(.sick, for: ana.id)

        XCTAssertThrowsError(try SiteMoving.apply(request(source: source, who: [ana.id]))) { error in
            XCTAssertEqual(error as? SiteMoveError, .notHere)
        }
    }

    func testLeavingOutsideTheirShiftIsRefused() {
        for left in [time(7), time(6), time(16), time(17)] {
            XCTAssertThrowsError(try SiteMoving.apply(request(left: left, started: time(17)))) { error in
                XCTAssertEqual(error as? SiteMoveError, .leftOutsideShift, "left at \(left.minutes)")
            }
        }
    }

    func testStartingBeforeLeavingIsRefused() {
        XCTAssertThrowsError(try SiteMoving.apply(request(left: time(11, 30), started: time(11)))) { error in
            XCTAssertEqual(error as? SiteMoveError, .startedBeforeLeft)
        }
    }

    func testStartingAfterTheDayEndsIsRefused() {
        XCTAssertThrowsError(try SiteMoving.apply(request(started: time(16)))) { error in
            XCTAssertEqual(error as? SiteMoveError, .startedAfterEnd)
        }
    }

    func testADayWithoutTimesCannotBeSplit() {
        var source = sourceDay()
        source.end = nil
        XCTAssertThrowsError(try SiteMoving.apply(request(source: source))) { error in
            XCTAssertEqual(error as? SiteMoveError, .noTimes)
        }
    }

    func testSomeoneWhoAlreadyMovedCannotMoveAgainFromHere() throws {
        let first = try SiteMoving.apply(request(who: [ivan.id]))
        XCTAssertThrowsError(try SiteMoving.apply(request(source: first.source, who: [ivan.id]))) { error in
            XCTAssertEqual(error as? SiteMoveError, .alreadyMoved)
        }
    }

    func testStartingTheMinuteTheyLeftIsAllowed() throws {
        let outcome = try SiteMoving.apply(request(started: time(11, 30)))
        XCTAssertEqual(outcome.target.start, time(11, 30))
    }

    // MARK: - Undo

    func testUndoRestoresBothDaysExactlyAndRemovesADayItCreated() throws {
        let source = sourceDay()
        let outcome = try SiteMoving.apply(request(source: source))

        let undone = SiteMoving.undo(outcome.move, source: outcome.source, target: outcome.target)

        XCTAssertEqual(undone.source, source)
        XCTAssertNil(undone.target)
    }

    func testUndoRestoresAnExistingDayExactly() throws {
        let existing = SiteDay(
            siteID: there.id,
            date: date,
            start: time(7),
            end: time(15),
            breakMinutes: 30,
            present: [Attendance(memberID: UUID()), Attendance(memberID: markoThere.id, start: time(9))],
            absences: [CrewAbsence(memberID: ivanThere.id, reason: .otherSite(here.id))],
            allowanceMemberIDs: [markoThere.id]
        )
        var site = there
        site.allowanceByDefault = true
        let outcome = try SiteMoving.apply(request(target: existing, tracksAllowance: true, targetSite: site))

        let undone = SiteMoving.undo(outcome.move, source: outcome.source, target: outcome.target)

        XCTAssertEqual(undone.source, sourceDay())
        XCTAssertEqual(undone.target, existing)
    }

    func testUndoKeepsADayItCreatedWhenSomethingElseWasWrittenOnItSince() throws {
        var outcome = try SiteMoving.apply(request(who: [ivan.id]))
        outcome.target.note = "Delivery at 14:00"

        let undone = SiteMoving.undo(outcome.move, source: outcome.source, target: outcome.target)

        XCTAssertEqual(undone.target?.note, "Delivery at 14:00")
        XCTAssertTrue(undone.target?.present.isEmpty ?? false)
    }

    func testUndoingOneMoveLeavesAnother() throws {
        let first = try SiteMoving.apply(request(who: [ivan.id]))
        let second = try SiteMoving.apply(request(source: first.source, target: first.target, who: [marko.id], left: time(13), started: time(13, 15)))

        let undone = SiteMoving.undo(first.move, source: second.source, target: second.target)

        XCTAssertEqual(undone.source.moves, [second.move])
        XCTAssertEqual(undone.source.resolved(for: ivan.id)?.end, time(16))
        XCTAssertEqual(undone.source.resolved(for: marko.id)?.end, time(13))
        XCTAssertEqual(undone.target?.present.map(\.memberID), [markoThere.id])
    }

    // MARK: - Your calendar

    func testYouGoingGivesYourCalendarDayTwoSiteShiftsCountedOnce() throws {
        let outcome = try SiteMoving.apply(request())

        let record = try XCTUnwrap(SiteCalendarSync.merged(
            personal: nil,
            siteDays: [outcome.source, outcome.target],
            on: date
        ))
        XCTAssertEqual(Set(record.shifts.compactMap(\.siteID)), [here.id, there.id])

        let settings = Fixture.settings()
        let day = WorkdayCalculator(settings: settings, calendar: Fixture.calendar()).compute(record: record, on: date)
        XCTAssertEqual(day.shifts.count, 2)
        XCTAssertEqual(day.workedMinutes, 480)
        XCTAssertEqual(day.breakMinutes, 30)
        XCTAssertEqual(day.shifts.map(\.siteID), [here.id, there.id], "in the order they were worked")
    }

    func testYouStayingLeavesYourCalendarAlone() throws {
        let outcome = try SiteMoving.apply(request(who: [ivan.id]))
        let record = SiteCalendarSync.merged(personal: nil, siteDays: [outcome.source, outcome.target], on: date)
        XCTAssertEqual(record?.shifts.count, 1)
        XCTAssertEqual(record?.shifts.first?.end, time(16))
    }

    // MARK: - Suggested times

    func testTheLeftTimeDefaultsToNowRounded() {
        let day = sourceDay()
        XCTAssertEqual(SiteMoving.suggestedLeftTime(for: day, now: time(11, 32), isToday: true, rounding: .exact), time(11, 30))
        XCTAssertEqual(SiteMoving.suggestedLeftTime(for: day, now: time(11, 38), isToday: true, rounding: .nearestQuarterHour), time(11, 45))
    }

    func testTheLeftTimeOutsideTheDayFallsBackToItsMiddle() {
        let day = sourceDay()
        XCTAssertEqual(SiteMoving.suggestedLeftTime(for: day, now: time(18), isToday: true, rounding: .exact), time(11, 30))
        XCTAssertEqual(SiteMoving.suggestedLeftTime(for: day, now: time(9), isToday: false, rounding: .exact), time(11, 30))
        var open = day
        open.end = nil
        XCTAssertEqual(SiteMoving.suggestedLeftTime(for: open, now: time(9), isToday: false, rounding: .exact), time(9))
    }

    // MARK: - Storing

    func testAMoveTravelsInTheAbsenceColumnAndOlderReadersSkipIt() throws {
        let outcome = try SiteMoving.apply(request())
        var source = outcome.source
        source = source.settingAbsence(.sick, for: UUID())

        let data = try XCTUnwrap(SiteDayStorage.absenceData(absences: source.absences, moves: source.moves))

        // What every build since 1.1 reads from the column: the reasons, entry by entry.
        XCTAssertEqual(CrewAbsence.decodeList(data), source.absences)
        XCTAssertEqual(SiteDayStorage.moves(fromAbsenceData: data), source.moves)
    }

    func testNoMovesAndNoAbsencesStoreNothing() {
        XCTAssertNil(SiteDayStorage.absenceData(absences: [], moves: []))
        XCTAssertEqual(SiteDayStorage.moves(fromAbsenceData: nil), [])
        XCTAssertEqual(SiteDayStorage.moves(fromAbsenceData: Data("junk".utf8)), [])
    }

    func testABackupCarriesMovesAndAnOldOneReadsAsNone() throws {
        let outcome = try SiteMoving.apply(request())
        let data = try JSONEncoder().encode(outcome.source)
        XCTAssertEqual(try JSONDecoder().decode(SiteDay.self, from: data), outcome.source)

        let plain = try JSONEncoder().encode(sourceDay())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("moves"), "a day without one is written as before")
        XCTAssertEqual(try JSONDecoder().decode(SiteDay.self, from: plain).moves, [])
    }
}
