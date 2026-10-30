import XCTest
@testable import Hours

/// The engine under the Today screen and the day editor's redesign (1.2):
/// the editor's Worked · Away · Day off, a half day of leave, "I worked the
/// usual day", a break on the running clock, and the crew days of today.
final class TodayScreenTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let catalog = DayTypeCatalog.standard

    // MARK: - Worked · Away · Day off

    func testEachBuiltInTypeHasItsKind() {
        func kind(_ id: DayTypeID) -> DayKind { DayKind.of(catalog.definition(for: id)) }

        XCTAssertEqual(kind(.work), .worked)
        XCTAssertEqual(kind(.other), .worked, "Other takes times, so it is a kind of work")
        XCTAssertEqual(kind(.vacation), .away)
        XCTAssertEqual(kind(.sick), .away)
        XCTAssertEqual(kind(.holiday), .away)
        XCTAssertEqual(kind(.personal), .away)
        XCTAssertEqual(kind(.badWeather), .away)
        XCTAssertEqual(kind(.timeOffInLieu), .away, "a day off against overtime is time away")
        XCTAssertEqual(kind(.dayOff), .dayOff)
        XCTAssertEqual(kind(.weekend), .dayOff)
    }

    func testTheAwayTypesAreInTheCataloguesOrder() {
        let away = catalog.types(of: .away).map(\.id)

        XCTAssertEqual(away, [.holiday, .vacation, .sick, .personal, .timeOffInLieu, .badWeather])
    }

    func testACustomScheduledTypeIsWork() {
        let training = DayTypeDefinition(
            id: DayTypeID("training"), name: "Training", symbolName: "book", tint: .purple,
            expectation: .scheduled, showsTimesByDefault: true, sortOrder: 80
        )

        XCTAssertEqual(DayKind.of(training), .worked)
    }

    func testSwitchingToAwayDropsYourOwnTimesAndKeepsTheSitesHours() {
        let site = Shift(start: Fixture.time(7), end: Fixture.time(11), siteID: UUID())
        let own = Shift(start: Fixture.time(12), end: Fixture.time(16))
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [site, own])

        let away = DayKind.away.apply(to: record, automatic: catalog.definition(for: .work), catalog: catalog, prefilled: own)

        XCTAssertEqual(away.dayTypeID, .vacation)
        XCTAssertEqual(away.shifts, [site], "a day of leave has none of your own hours on it")
    }

    func testSwitchingToAwayKeepsATypeAlreadyAway() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)

        let away = DayKind.away.apply(to: record, automatic: catalog.definition(for: .work), catalog: catalog, prefilled: Shift())

        XCTAssertEqual(away.dayTypeID, .sick)
    }

    func testSwitchingToAwayOnAPublicHolidayLeavesItAutomatic() {
        let record = DayRecord(date: Fixture.workingTuesday)

        let away = DayKind.away.apply(to: record, automatic: catalog.definition(for: .holiday), catalog: catalog, prefilled: Shift())

        XCTAssertNil(away.dayTypeID, "the holiday rule already makes it a paid day off")
    }

    func testSwitchingToWorkedOnAWorkingDayIsAutomaticWithTheUsualTimes() {
        let usual = Shift(start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)

        let worked = DayKind.worked.apply(to: record, automatic: catalog.definition(for: .work), catalog: catalog, prefilled: usual)

        XCTAssertNil(worked.dayTypeID)
        XCTAssertEqual(worked.shifts, [usual])
    }

    func testSwitchingToWorkedOnASaturdayMakesItWork() {
        let usual = Shift(start: Fixture.time(8), end: Fixture.time(12))
        let record = DayRecord(date: Fixture.saturday)

        let worked = DayKind.worked.apply(to: record, automatic: catalog.definition(for: .weekend), catalog: catalog, prefilled: usual)

        XCTAssertEqual(worked.dayTypeID, .work)
        XCTAssertEqual(worked.shifts, [usual])
    }

    func testSwitchingToWorkedKeepsTimesAlreadyThere() {
        let own = Shift(start: Fixture.time(6), end: Fixture.time(9))
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick, shifts: [own])

        let worked = DayKind.worked.apply(
            to: record, automatic: catalog.definition(for: .work), catalog: catalog,
            prefilled: Shift(start: Fixture.time(8), end: Fixture.time(16))
        )

        XCTAssertEqual(worked.shifts, [own])
    }

    func testSwitchingToDayOffClearsTimesAndAHalfDay() {
        var record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation, shifts: [Shift(start: Fixture.time(8), end: Fixture.time(12))])
        record.expectedOverrideMinutes = 240

        let off = DayKind.dayOff.apply(
            to: record, automatic: catalog.definition(for: .work), catalog: catalog, prefilled: Shift(), contractedMinutes: 480
        )

        XCTAssertEqual(off.dayTypeID, .dayOff)
        XCTAssertTrue(off.shifts.isEmpty)
        XCTAssertNil(off.expectedOverrideMinutes, "a half day belongs to the leave, not to the day off")
    }

    func testSwitchingKeepsExpectedHoursSetForAnotherReason() {
        var record = DayRecord(date: Fixture.workingTuesday)
        record.expectedOverrideMinutes = 360

        let away = DayKind.away.apply(
            to: record, automatic: catalog.definition(for: .work), catalog: catalog, prefilled: Shift(), contractedMinutes: 480
        )

        XCTAssertEqual(away.expectedOverrideMinutes, 360)
    }

    func testSwitchingToDayOffOnAWeekendLeavesItAutomatic() {
        let off = DayKind.dayOff.apply(
            to: DayRecord(date: Fixture.saturday), automatic: catalog.definition(for: .weekend), catalog: catalog, prefilled: Shift()
        )

        XCTAssertNil(off.dayTypeID)
    }

    // MARK: - Half a day

    func testAHalfDayIsHalfTheContractedHours() {
        XCTAssertEqual(HalfDay.minutes(contracted: 480), 240)
        XCTAssertEqual(HalfDay.minutes(contracted: 510), 255)
    }

    func testAHalfDayIsReadBackFromTheExpectedHours() {
        XCTAssertTrue(HalfDay.isHalf(expectedOverride: 240, contracted: 480))
        XCTAssertFalse(HalfDay.isHalf(expectedOverride: nil, contracted: 480))
        XCTAssertFalse(HalfDay.isHalf(expectedOverride: 480, contracted: 480))
        XCTAssertFalse(HalfDay.isHalf(expectedOverride: 0, contracted: 480), "nothing credited is not half a day")
        XCTAssertFalse(HalfDay.isHalf(expectedOverride: 240, contracted: 0))
    }

    func testAHalfDayOfVacationTakesHalfADayOfLeave() {
        let settings = Fixture.settings()
        var record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        record.expectedOverrideMinutes = HalfDay.minutes(contracted: settings.contractedMinutes(on: Fixture.workingTuesday, calendar: calendar))
        let day = Fixture.engine(settings: settings).day(Fixture.workingTuesday, record: record, holidays: [])

        XCTAssertEqual(LeaveCalculator.halfDays(for: day, settings: settings, calendar: calendar), 1)
    }

    // MARK: - I worked the usual day

    func testTheUsualDayIsTheScheduleOnAnEmptyDay() {
        let settings = Fixture.settings()
        let record = UsualDay.record(for: Fixture.workingTuesday, existing: nil, engine: Fixture.engine(settings: settings), holidays: [])

        XCTAssertEqual(record?.shifts.count, 1)
        XCTAssertEqual(record?.shifts.first?.start, settings.prefilledShift(on: Fixture.workingTuesday).start)
        XCTAssertEqual(record?.shifts.first?.end, settings.prefilledShift(on: Fixture.workingTuesday).end)
    }

    func testTheUsualDayKeepsTheSitesHoursAndWhatElseIsWritten() {
        let site = Shift(start: Fixture.time(7), end: Fixture.time(9), siteID: UUID())
        var existing = DayRecord(date: Fixture.workingTuesday, shifts: [site])
        existing.note = "Concrete"

        let record = UsualDay.record(for: Fixture.workingTuesday, existing: existing, engine: Fixture.engine(), holidays: [])

        XCTAssertEqual(record?.shifts.first, site)
        XCTAssertEqual(record?.shifts.count, 2)
        XCTAssertEqual(record?.note, "Concrete")
    }

    func testTheUsualDayIsNotOfferedOverHoursAlreadyWritten() {
        let existing = DayRecord(date: Fixture.workingTuesday, shifts: [Shift(start: Fixture.time(8), end: Fixture.time(12))])

        XCTAssertNil(UsualDay.record(for: Fixture.workingTuesday, existing: existing, engine: Fixture.engine(), holidays: []))
    }

    func testTheUsualDayIsNotOfferedOverAFigureTypedByHand() {
        var existing = DayRecord(date: Fixture.workingTuesday)
        existing.manualWorkedMinutes = 300

        XCTAssertNil(UsualDay.record(for: Fixture.workingTuesday, existing: existing, engine: Fixture.engine(), holidays: []))
    }

    func testTheUsualDayOnASaturdayStillHasTimes() {
        let record = UsualDay.record(for: Fixture.saturday, existing: nil, engine: Fixture.engine(), holidays: [])

        XCTAssertEqual(record?.shifts.count, 1, "you said you worked it")
    }

    // MARK: - A break on the running clock

    private func instant(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: hour, minute: minute)) ?? Date()
    }

    private func times(_ breaks: [BreakSpan]) -> [[TimeOfDay?]] {
        breaks.map { [$0.start, $0.end] }
    }

    func testABreakIsTakenAndEnded() {
        let running = RunningShift(startingAt: instant(7), calendar: calendar)
        let onBreak = running.startingBreak(at: instant(12), calendar: calendar)

        XCTAssertTrue(onBreak.isOnBreak)
        XCTAssertEqual(onBreak.breakStart, Fixture.time(12))

        let back = onBreak.endingBreak(at: instant(12, 30), calendar: calendar)
        XCTAssertFalse(back.isOnBreak)
        XCTAssertEqual(times(back.breaks), [[Fixture.time(12), Fixture.time(12, 30)]])
    }

    func testWorkedTimeLeavesBreaksOut() {
        let running = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(12), calendar: calendar)
            .endingBreak(at: instant(12, 30), calendar: calendar)

        XCTAssertEqual(running.workedSeconds(at: instant(16)), 8 * 3600 + 30 * 60)
        XCTAssertEqual(running.elapsedSeconds(at: instant(16)), 9 * 3600, "elapsed is still the whole time")
    }

    func testWorkedTimeStandsStillDuringABreak() {
        let onBreak = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(12), calendar: calendar)

        XCTAssertEqual(onBreak.workedSeconds(at: instant(12, 20)), 5 * 3600)
    }

    func testStoppingRecordsTheBreaks() {
        let running = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(12), calendar: calendar)
            .endingBreak(at: instant(12, 30), calendar: calendar)

        let shift = running.finished(at: instant(16), calendar: calendar)

        XCTAssertEqual(times(shift.breaks), [[Fixture.time(12), Fixture.time(12, 30)]])
    }

    func testStoppingDuringABreakEndsItThere() {
        let onBreak = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(15, 45), calendar: calendar)

        let shift = onBreak.finished(at: instant(16), calendar: calendar)

        XCTAssertEqual(times(shift.breaks), [[Fixture.time(15, 45), Fixture.time(16)]])
    }

    func testStartingABreakTwiceKeepsTheFirst() {
        let onBreak = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(12), calendar: calendar)
            .startingBreak(at: instant(12, 10), calendar: calendar)

        XCTAssertEqual(onBreak.breakStart, Fixture.time(12))
    }

    func testAClockSavedBeforeBreaksStillLoads() throws {
        // Whatever the stored shape of a date and a time is, an old clock
        // written without breaks reads back with none rather than failing:
        // the running clock is kept in UserDefaults across an update.
        let encoded = try JSONEncoder().encode(RunningShift(startingAt: instant(7), calendar: calendar))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "breaks")
        object.removeValue(forKey: "breakStartedAt")
        object.removeValue(forKey: "breakStart")
        object.removeValue(forKey: "breakSeconds")
        let withoutBreaks = try JSONSerialization.data(withJSONObject: object)

        let loaded = try JSONDecoder().decode(RunningShift.self, from: withoutBreaks)
        XCTAssertTrue(loaded.breaks.isEmpty)
        XCTAssertFalse(loaded.isOnBreak)
        XCTAssertEqual(loaded.start, Fixture.time(7))
    }

    func testAClockWithABreakRoundTrips() throws {
        let onBreak = RunningShift(startingAt: instant(7), calendar: calendar)
            .startingBreak(at: instant(9), calendar: calendar)
            .endingBreak(at: instant(9, 15), calendar: calendar)
            .startingBreak(at: instant(12), calendar: calendar)

        let loaded = try JSONDecoder().decode(RunningShift.self, from: JSONEncoder().encode(onBreak))

        XCTAssertEqual(loaded, onBreak)
    }

    // MARK: - Today's crew days

    func testASiteExpectedTodayWithNothingWrittenAsksForIt() {
        let site = Site(name: "Trg Pravde")

        let rows = CrewDayToday.rows(
            sites: [site], written: [:], expected: [site.id], coworkers: [site.id: 4], crewMinutes: { _ in 0 }
        )

        XCTAssertEqual(rows, [CrewDayToday.Row(siteID: site.id, siteName: "Trg Pravde", isWritten: false, people: 5, crewMinutes: nil)])
    }

    func testAWrittenSiteSaysWhoWasThereAndTheHours() {
        let site = Site(name: "Jarun")
        let day = SiteDay(
            siteID: site.id, date: Fixture.workingTuesday,
            present: [Attendance(memberID: UUID()), Attendance(memberID: UUID()), Attendance(memberID: CrewMember.youID)]
        )

        let rows = CrewDayToday.rows(
            sites: [site], written: [site.id: day], expected: [], coworkers: [site.id: 4], crewMinutes: { _ in 1530 }
        )

        XCTAssertEqual(rows, [CrewDayToday.Row(siteID: site.id, siteName: "Jarun", isWritten: true, people: 3, crewMinutes: 1530)])
    }

    func testASiteWithNoWorkTodayAndArchivedSitesAreLeftOut() {
        let quiet = Site(name: "Quiet")
        let archived = Site(name: "Old", isArchived: true)

        let rows = CrewDayToday.rows(
            sites: [quiet, archived], written: [:], expected: [archived.id], coworkers: [:], crewMinutes: { _ in 0 }
        )

        XCTAssertTrue(rows.isEmpty)
    }

    func testRowsFollowTheSitesOrder() {
        let second = Site(name: "B", sortOrder: 2)
        let first = Site(name: "A", sortOrder: 1)

        let rows = CrewDayToday.rows(
            sites: [second, first], written: [:], expected: [first.id, second.id], coworkers: [:], crewMinutes: { _ in 0 }
        )

        XCTAssertEqual(rows.map(\.siteName), ["A", "B"])
    }
    // MARK: - Edit a range: leave left after

    func testLeaveLeftAfterBookingAFortnight() {
        let settings = Fixture.settings()
        // Monday 3 to Friday 14 August 2026: ten working days, two weekends.
        let request = BulkEditRequest(
            range: CalendarDateRange(start: Fixture.date(2026, 8, 3), end: Fixture.date(2026, 8, 14)),
            action: .setDayType(.vacation)
        )
        let plan = BulkEditor.plan(request, existing: [:], settings: settings, calendar: calendar)

        let left = BulkEditLeave.remaining(
            after: plan, on: request.range.start, records: [:],
            engine: Fixture.engine(settings: settings), holidays: [], today: Fixture.date(2026, 7, 1)
        )

        XCTAssertEqual(left, HalfDays(days: settings.leave.allowanceDays - 10))
    }

    func testClearingLeaveGivesItBack() {
        let settings = Fixture.settings()
        let booked = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        let records = [booked.date.key: booked]
        let request = BulkEditRequest(
            range: CalendarDateRange(single: Fixture.workingTuesday), action: .clear, overwritesExistingEntries: true
        )
        let plan = BulkEditor.plan(request, existing: records, settings: settings, calendar: calendar)

        let left = BulkEditLeave.remaining(
            after: plan, on: Fixture.workingTuesday, records: records,
            engine: Fixture.engine(settings: settings), holidays: [], today: Fixture.date(2026, 7, 1)
        )

        XCTAssertEqual(plan.deletions, [Fixture.workingTuesday])
        XCTAssertEqual(left, HalfDays(days: settings.leave.allowanceDays))
    }

    func testAPlanAppliedReplacesAndDeletes() {
        let kept = DayRecord(date: Fixture.workingMonday, note: "kept")
        let cleared = DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        let plan = BulkEditPlan(
            changes: [DayRecord(date: Fixture.saturday, dayTypeID: .vacation)],
            deletions: [Fixture.workingTuesday],
            skippedExisting: 0,
            skippedNonWorking: 0
        )

        let after = plan.applied(to: [kept.date.key: kept, cleared.date.key: cleared])

        XCTAssertEqual(after[kept.date.key], kept)
        XCTAssertNil(after[cleared.date.key])
        XCTAssertEqual(after[Fixture.saturday.key]?.dayTypeID, .vacation)
    }
}
