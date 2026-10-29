import XCTest
import SwiftData
@testable import Hours

/// Site days, and the supervisor's own calendar day kept in step with them.
///
/// The two failures these exist to catch are a save that silently does
/// nothing and a site day that disagrees with the calendar. So nearly every
/// test reads both stores back afterwards, not only the one it wrote.
@MainActor
final class SiteRepositoryTests: XCTestCase {
    private let date = Fixture.workingTuesday
    private let site = Site(name: "Hauptstraße 12", jobID: UUID())
    private let ivan = UUID()

    private func makeContext() -> ModelContext {
        ModelContext(HoursModelContainer.ephemeral())
    }

    private func crewDay(
        on date: CalendarDate? = nil,
        start: Int = 7,
        end: Int = 16,
        breakMinutes: Int = 30,
        withYou: Bool = true
    ) -> SiteDay {
        var present = [Attendance(memberID: ivan)]
        if withYou { present.insert(Attendance(memberID: CrewMember.youID), at: 0) }
        return SiteDay(
            siteID: site.id,
            date: date ?? self.date,
            start: Fixture.time(start),
            end: Fixture.time(end),
            breakMinutes: breakMinutes,
            present: present,
            note: "rain after lunch",
            jobID: site.jobID
        )
    }

    private func siteShifts(_ record: DayRecord?) -> [Shift] {
        record?.shifts.filter { $0.siteID != nil } ?? []
    }

    private func siteDayCount(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<SiteDayEntry>())) ?? 0
    }

    private func dayCount(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
    }

    /// Inserts straight into the context, bypassing `save`, which is exactly
    /// what a sync merge does.
    private func insertRaw(_ day: SiteDay, into context: ModelContext, updatedAt: Date, createdAt: Date? = nil) {
        let entry = SiteDayEntry(day: day)
        entry.createdAt = createdAt ?? updatedAt
        entry.updatedAt = updatedAt
        context.insert(entry)
        try? context.save()
    }

    // MARK: - Saving

    func testSaveWritesYourCalendarShift() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)
        let manual = Shift(start: Fixture.time(18), end: Fixture.time(20))
        try workdays.save(DayRecord(date: date, shifts: [manual], note: "evening job"))

        try repository.save(crewDay())

        XCTAssertEqual(repository.siteDay(siteID: site.id, on: date), crewDay())
        let record = workdays.record(on: date)
        let shifts = siteShifts(record)
        XCTAssertEqual(shifts.count, 1)
        XCTAssertEqual(shifts.first?.siteID, site.id)
        XCTAssertEqual(shifts.first?.start, Fixture.time(7))
        XCTAssertEqual(shifts.first?.end, Fixture.time(16))
        XCTAssertEqual(shifts.first?.breaks.map(\.minutes), [30])
        XCTAssertEqual(shifts.first?.jobID, site.jobID, "the shift counts towards the job frozen on the day")
        XCTAssertTrue(record?.shifts.contains(manual) ?? false, "your own shift that day is left alone")
        XCTAssertEqual(record?.note, "evening job")

        // Saving again replaces the site shift rather than adding a second.
        try repository.save(crewDay(start: 8, end: 17))

        let resaved = siteShifts(workdays.record(on: date))
        XCTAssertEqual(resaved.count, 1)
        XCTAssertEqual(resaved.first?.start, Fixture.time(8))
        XCTAssertEqual(resaved.first?.end, Fixture.time(17))
        XCTAssertEqual(siteDayCount(context), 1)
        XCTAssertEqual(dayCount(context), 1)
    }

    /// A day you were not on still records the crew, and puts nothing in your
    /// calendar — and unticking yourself later takes the shift back out.
    func testUntickingYouTakesTheShiftOutOfYourCalendar() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)

        try repository.save(crewDay())
        XCTAssertEqual(siteShifts(workdays.record(on: date)).count, 1)

        try repository.save(crewDay(withYou: false))

        XCTAssertNotNil(repository.siteDay(siteID: site.id, on: date), "the crew's day is still recorded")
        XCTAssertNil(workdays.record(on: date), "a calendar day left with nothing in it is not stored")
        XCTAssertEqual(dayCount(context), 0)
    }

    /// Your day can hold shifts from two sites; saving one must not drop the other.
    func testTwoSitesOnOneDayBothReachYourCalendar() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)
        let other = Site(name: "Bahnhof")
        let morning = crewDay(start: 7, end: 11, breakMinutes: 0)
        let afternoon = SiteDay(
            siteID: other.id,
            date: date,
            start: Fixture.time(12),
            end: Fixture.time(16),
            present: [Attendance(memberID: CrewMember.youID)]
        )

        try repository.save(morning)
        try repository.save(afternoon)

        let shifts = siteShifts(workdays.record(on: date))
        XCTAssertEqual(Set(shifts.compactMap(\.siteID)), [site.id, other.id])
        XCTAssertEqual(shifts.count, 2)
        XCTAssertEqual(repository.siteDays(siteID: nil, in: CalendarDateRange(start: date, end: date)).count, 2)
    }

    // MARK: - The month lock

    func testLockedMonthRefusesAndChangesNothing() throws {
        let context = makeContext()
        try SiteRepository(context: context).save(crewDay())
        let workdays = WorkdayRepository(context: context)
        let siteDayBefore = SiteRepository(context: context).siteDay(siteID: site.id, on: date)
        let recordBefore = workdays.record(on: date)

        let lock = MonthLock(months: [YearMonth(date)])
        let locked = SiteRepository(context: context, lock: lock)

        XCTAssertThrowsError(try locked.save(crewDay(start: 9, end: 18))) { error in
            XCTAssertEqual(error as? MonthLock.Refusal, .monthIsClosed(YearMonth(date)))
        }
        XCTAssertThrowsError(try locked.save(crewDay(withYou: false))) { error in
            XCTAssertEqual(error as? MonthLock.Refusal, .monthIsClosed(YearMonth(date)))
        }
        XCTAssertThrowsError(try locked.delete(siteID: site.id, on: date)) { error in
            XCTAssertEqual(error as? MonthLock.Refusal, .monthIsClosed(YearMonth(date)))
        }

        XCTAssertFalse(context.hasChanges, "nothing was half-written and left pending either")
        XCTAssertEqual(locked.siteDay(siteID: site.id, on: date), siteDayBefore)
        XCTAssertEqual(workdays.record(on: date), recordBefore)
        XCTAssertEqual(siteDayCount(context), 1)
        XCTAssertEqual(dayCount(context), 1)

        // A new day in a closed month is refused just the same, and leaves nothing behind.
        let otherDate = Fixture.date(2026, 8, 5)
        XCTAssertThrowsError(try locked.save(crewDay(on: otherDate)))
        XCTAssertNil(locked.siteDay(siteID: site.id, on: otherDate))
        XCTAssertNil(workdays.record(on: otherDate))

        // The month next door is open.
        let september = Fixture.date(2026, 9, 1)
        XCTAssertNoThrow(try locked.save(crewDay(on: september)))
        XCTAssertEqual(siteShifts(workdays.record(on: september)).count, 1)
    }

    // MARK: - Deleting

    func testDeletingSiteDayRemovesCalendarShift() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)
        let manual = Shift(start: Fixture.time(18), end: Fixture.time(20))
        try workdays.save(DayRecord(date: date, shifts: [manual]))
        try repository.save(crewDay())
        let lonelyDate = Fixture.date(2026, 8, 6)
        try repository.save(crewDay(on: lonelyDate))

        try repository.delete(siteID: site.id, on: date)
        try repository.delete(siteID: site.id, on: lonelyDate)

        XCTAssertNil(repository.siteDay(siteID: site.id, on: date))
        XCTAssertEqual(workdays.record(on: date)?.shifts, [manual], "only the site's shift goes")
        XCTAssertNil(workdays.record(on: lonelyDate), "a day that held nothing else goes with it")
        XCTAssertEqual(siteDayCount(context), 0)
        XCTAssertEqual(dayCount(context), 1)
    }

    // MARK: - Duplicates

    /// Review Focus 4: two devices recorded the same site day offline.
    func testDuplicateSiteDaysCollapseToNewest() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)

        // Each device wrote its own site day and carried it into the calendar;
        // the calendar rows reconcile on their own, so leave the older one.
        try repository.save(crewDay(start: 6, end: 14))
        insertRaw(crewDay(start: 9, end: 18), into: context, updatedAt: Date().addingTimeInterval(60))
        XCTAssertEqual(siteDayCount(context), 2)

        XCTAssertEqual(repository.reconcileDuplicates(), 1)

        XCTAssertEqual(siteDayCount(context), 1, "the losing row is removed, not merely hidden")
        XCTAssertEqual(repository.siteDay(siteID: site.id, on: date)?.start, Fixture.time(9))
        let shifts = siteShifts(workdays.record(on: date))
        XCTAssertEqual(shifts.count, 1, "exactly one shift for the site that day")
        XCTAssertEqual(shifts.first?.start, Fixture.time(9), "and it agrees with the site day that won")
        XCTAssertEqual(shifts.first?.end, Fixture.time(18))
    }

    /// Reading the day collapses it too, and still leaves the calendar agreeing.
    func testReadingADuplicatedSiteDayKeepsTheCalendarInStep() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let workdays = WorkdayRepository(context: context)
        try repository.save(crewDay(start: 6, end: 14))
        insertRaw(crewDay(start: 9, end: 18), into: context, updatedAt: Date().addingTimeInterval(60))

        XCTAssertEqual(repository.siteDay(siteID: site.id, on: date)?.start, Fixture.time(9))

        XCTAssertEqual(siteDayCount(context), 1)
        XCTAssertEqual(siteShifts(workdays.record(on: date)).map(\.start), [Fixture.time(9)])
    }

    /// The same rule as `WorkdayRepository`: rows nothing can tell apart are
    /// all kept, because two devices breaking the tie differently would each
    /// delete what the other kept.
    func testSiteDaysNothingCanTellApartAreBothKept() {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let sameInstant = Date(timeIntervalSince1970: 500)
        insertRaw(crewDay(start: 6), into: context, updatedAt: sameInstant, createdAt: sameInstant)
        insertRaw(crewDay(start: 9), into: context, updatedAt: sameInstant, createdAt: sameInstant)

        XCTAssertEqual(repository.reconcileDuplicates(), 0, "a tie is not a licence to delete")
        XCTAssertEqual(siteDayCount(context), 2)
        XCTAssertNotNil(repository.siteDay(siteID: site.id, on: date))
        XCTAssertEqual(
            repository.siteDays(siteID: site.id, in: CalendarDateRange(start: date, end: date)).count, 1,
            "a read still shows the day once"
        )
    }

    func testDuplicateSitesAndCrewCollapseToNewest() {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let old = SiteEntry(site: Site(id: site.id, name: "Old name"))
        old.updatedAt = Date(timeIntervalSince1970: 100)
        let new = SiteEntry(site: Site(id: site.id, name: "New name"))
        new.updatedAt = Date(timeIntervalSince1970: 200)
        let member = CrewMember(id: ivan, siteID: site.id, name: "Ivan")
        let staleMember = CrewMemberEntry(member: member)
        staleMember.updatedAt = Date(timeIntervalSince1970: 100)
        let freshMember = CrewMemberEntry(member: CrewMember(id: ivan, siteID: site.id, name: "Ivan H."))
        freshMember.updatedAt = Date(timeIntervalSince1970: 200)
        context.insert(new)
        context.insert(old)
        context.insert(freshMember)
        context.insert(staleMember)
        try? context.save()

        XCTAssertEqual(repository.reconcileDuplicates(), 2)
        XCTAssertEqual(repository.sites(includeArchived: true).map(\.name), ["New name"])
        XCTAssertEqual(repository.crew(for: site.id, includeHidden: true).map(\.name), ["Ivan H."])
    }

    // MARK: - Same as last day

    func testSameAsLastDayCopiesTimesAndCrewNotExceptions() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        repository.upsert(site)
        var leaver = CrewMember(siteID: site.id, name: "Goran")
        repository.upsert(leaver)
        let monday = Fixture.workingMonday
        let lastDay = SiteDay(
            siteID: site.id,
            date: monday,
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 45,
            present: [
                Attendance(memberID: CrewMember.youID),
                Attendance(memberID: ivan, end: Fixture.time(12), breakMinutes: 0),
                Attendance(memberID: leaver.id),
            ],
            note: "rain, stopped at 13:00",
            jobID: site.jobID
        )
        try repository.save(lastDay)
        // An older day must not win over the most recent one.
        try repository.save(SiteDay(siteID: site.id, date: Fixture.date(2026, 7, 30), start: Fixture.time(5)))

        // The site has moved to another job since.
        var moved = site
        moved.jobID = UUID()
        repository.upsert(moved)
        // And Goran has left the crew since.
        leaver.isHidden = true
        repository.upsert(leaver)

        let thursday = Fixture.date(2026, 8, 6)
        let copy = try XCTUnwrap(repository.sameAsLastDay(siteID: site.id, on: thursday))

        XCTAssertEqual(copy.siteID, site.id)
        XCTAssertEqual(copy.date, thursday)
        XCTAssertEqual(copy.start, Fixture.time(7))
        XCTAssertEqual(copy.end, Fixture.time(16))
        XCTAssertEqual(copy.breakMinutes, 45)
        XCTAssertEqual(copy.present.map(\.memberID), [CrewMember.youID, ivan], "you carry over; someone who has left does not")
        XCTAssertNil(copy.attendance(for: leaver.id))
        XCTAssertFalse(copy.hasException(ivan), "Ivan leaving early was that day's exception, not this one's")
        XCTAssertEqual(copy.note, "", "the note was about that day")
        XCTAssertEqual(copy.jobID, moved.jobID, "a new day takes the site's job as it is now")

        XCTAssertNil(repository.siteDay(siteID: site.id, on: thursday), "the copy is not saved until you save it")
        XCTAssertNil(repository.sameAsLastDay(siteID: site.id, on: Fixture.date(2026, 7, 30)), "nothing earlier to copy")
    }

    /// The same crew driving to the same site: who had the field allowance
    /// and the vehicle's kilometres carry over; someone left out of the copy
    /// takes their allowance with them.
    func testSameAsLastDayCopiesTheAllowanceAndKilometres() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        repository.upsert(site)
        var leaver = CrewMember(siteID: site.id, name: "Goran", sortOrder: 2)
        repository.upsert(leaver)
        var lastDay = crewDay(on: Fixture.workingMonday)
            .togglingPresence(of: leaver.id, allowanceByDefault: true)
            .settingAllowance(true, for: ivan)
        lastDay.kilometres = 84
        try repository.save(lastDay)
        leaver.isHidden = true
        repository.upsert(leaver)

        let copy = try XCTUnwrap(repository.sameAsLastDay(siteID: site.id, on: Fixture.date(2026, 8, 6)))
        XCTAssertEqual(copy.allowanceMemberIDs, [ivan])
        XCTAssertEqual(copy.kilometres, 84)
    }

    /// People are sick a day at a time: a reason never carries over.
    func testSameAsLastDayDoesNotCopyAbsences() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        repository.upsert(site)
        let ana = UUID()
        let lastDay = crewDay(on: Fixture.workingMonday)
            .settingAbsence(.sick, for: ana)
            .settingAbsence(.vacation, for: CrewMember.youID)
        try repository.save(lastDay)

        let copy = try XCTUnwrap(repository.sameAsLastDay(siteID: site.id, on: Fixture.date(2026, 8, 6)))
        XCTAssertEqual(copy.absences, [])
        XCTAssertEqual(copy.present.map(\.memberID), [ivan])
    }

    /// You away sick on the site: your calendar day is a sick day, in the
    /// same save. Ticking yourself back in makes it a working day again.
    func testYouAwayWithAReasonTypesYourCalendarDay() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        repository.upsert(site)
        let sick = crewDay(withYou: false).settingAbsence(.sick, for: CrewMember.youID)
        try repository.save(sick)

        let workdays = WorkdayRepository(context: context)
        XCTAssertEqual(workdays.record(on: date)?.dayTypeID, .sick)
        XCTAssertEqual(repository.siteDay(siteID: site.id, on: date)?.absence(for: CrewMember.youID), .sick)

        try repository.save(sick.togglingPresence(of: CrewMember.youID))
        XCTAssertNil(workdays.record(on: date)?.dayTypeID)
        XCTAssertEqual(siteShifts(workdays.record(on: date)).count, 1)
    }

    // MARK: - Sites, crew and restore

    func testSitesAndCrewReadBackFilteredAndInOrder() {
        let repository = SiteRepository(context: makeContext())
        let archived = Site(name: "Finished", isArchived: true, sortOrder: 0)
        let second = Site(name: "Second", sortOrder: 2)
        repository.upsert(second)
        repository.upsert(site)
        repository.upsert(archived)
        var renamed = site
        renamed.sortOrder = 1
        renamed.name = "Hauptstraße 14"
        repository.upsert(renamed)

        XCTAssertEqual(repository.sites(includeArchived: false), [renamed, second])
        XCTAssertEqual(repository.sites(includeArchived: true), [archived, renamed, second])

        let hidden = CrewMember(siteID: site.id, name: "Left", isHidden: true, sortOrder: 0)
        let shown = CrewMember(id: ivan, siteID: site.id, name: "Ivan", sortOrder: 1)
        let elsewhere = CrewMember(siteID: second.id, name: "Marko")
        for member in [shown, hidden, elsewhere] { repository.upsert(member) }

        XCTAssertEqual(repository.crew(for: site.id, includeHidden: false), [shown])
        XCTAssertEqual(repository.crew(for: site.id, includeHidden: true), [hidden, shown])
    }

    func testReplaceAllMakesTheGivenDataTheWholeStore() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        repository.upsert(Site(name: "Gone"))
        try repository.save(crewDay())

        let restored = Site(name: "From the file")
        let member = CrewMember(siteID: restored.id, name: "Ana")
        let day = SiteDay(siteID: restored.id, date: date, start: Fixture.time(8), present: [Attendance(memberID: member.id)])
        repository.replaceAll(sites: [restored], crew: [member], siteDays: [day])

        XCTAssertEqual(repository.sites(includeArchived: true), [restored])
        XCTAssertEqual(repository.crew(for: restored.id, includeHidden: true), [member])
        XCTAssertEqual(repository.siteDays(siteID: nil, in: CalendarDateRange(start: date, end: date)), [day])
        XCTAssertEqual(siteDayCount(context), 1)
    }

    // MARK: - Moving to another site (1.2)

    private func move(_ repository: SiteRepository, to other: Site, crew: [CrewMember] = []) throws -> SiteMoveOutcome {
        let source = try XCTUnwrap(repository.siteDay(siteID: site.id, on: date))
        let outcome = try SiteMoving.apply(SiteMoveRequest(
            source: source,
            target: repository.siteDay(siteID: other.id, on: date),
            targetSite: other,
            sourceCrew: crew,
            targetCrew: repository.crew(for: other.id, includeHidden: true),
            memberIDs: [CrewMember.youID, ivan],
            left: Fixture.time(11),
            started: Fixture.time(12),
            breakPlacement: .there,
            lock: repository.lock,
            tracksAllowance: false
        ))
        try repository.applyMove(outcome)
        return outcome
    }

    func testAMoveStoresBothDaysTheNewCrewAndTwoShiftsInYourCalendar() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let other = Site(name: "Trg Pravde", jobID: UUID())
        repository.upsert(site)
        repository.upsert(other)
        let member = CrewMember(id: ivan, siteID: site.id, name: "Ivan")
        repository.upsert(member)
        try repository.save(crewDay())

        let outcome = try move(repository, to: other, crew: [member])

        let stored = try XCTUnwrap(repository.siteDay(siteID: site.id, on: date))
        XCTAssertEqual(stored.moves, [outcome.move], "the move survives the store")
        XCTAssertEqual(stored.resolved(for: ivan)?.end, Fixture.time(11))
        XCTAssertEqual(repository.siteDay(siteID: other.id, on: date), outcome.target)
        XCTAssertEqual(repository.crew(for: other.id, includeHidden: true).map(\.name), ["Ivan"])

        let record = WorkdayRepository(context: context).record(on: date)
        XCTAssertEqual(Set(siteShifts(record).compactMap(\.siteID)), [site.id, other.id])
    }

    func testUndoingAMoveTakesBothDaysAndYourCalendarBack() throws {
        let context = makeContext()
        let repository = SiteRepository(context: context)
        let other = Site(name: "Trg Pravde")
        repository.upsert(site)
        repository.upsert(other)
        try repository.save(crewDay())
        let before = try XCTUnwrap(repository.siteDay(siteID: site.id, on: date))
        let outcome = try move(repository, to: other)

        try repository.undoMove(outcome.move, from: outcome.source)

        XCTAssertEqual(repository.siteDay(siteID: site.id, on: date), before)
        XCTAssertNil(repository.siteDay(siteID: other.id, on: date))
        let record = WorkdayRepository(context: context).record(on: date)
        XCTAssertEqual(siteShifts(record).map(\.siteID), [site.id])
        XCTAssertEqual(siteShifts(record).first?.end, Fixture.time(16))
    }

    func testAMoveIntoAClosedMonthIsRefused() throws {
        let context = makeContext()
        let open = SiteRepository(context: context)
        let other = Site(name: "Trg Pravde")
        open.upsert(site)
        open.upsert(other)
        try open.save(crewDay())
        let outcome = try move(open, to: other)
        let locked = SiteRepository(context: context, lock: MonthLock(months: [YearMonth(date)]))

        XCTAssertThrowsError(try locked.applyMove(outcome))
        XCTAssertThrowsError(try locked.undoMove(outcome.move, from: outcome.source))
        XCTAssertEqual(open.siteDay(siteID: site.id, on: date)?.moves, [outcome.move])
    }
}
