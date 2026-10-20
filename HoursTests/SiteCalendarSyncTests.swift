import XCTest
@testable import Hours

final class SiteCalendarSyncTests: XCTestCase {
    private let siteA = UUID()
    private let siteB = UUID()
    private let date = Fixture.workingTuesday

    private func siteDay(
        _ siteID: UUID,
        present: [Attendance] = [Attendance(memberID: CrewMember.youID)],
        jobID: UUID? = nil,
        date: CalendarDate? = nil
    ) -> SiteDay {
        SiteDay(
            siteID: siteID,
            date: date ?? self.date,
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present,
            jobID: jobID
        )
    }

    func testTickingYouAddsOneSiteShift() {
        let job = UUID()
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay(siteA, jobID: job)], on: date)

        XCTAssertEqual(merged?.shifts.count, 1)
        let shift = merged?.shifts.first
        XCTAssertEqual(shift?.siteID, siteA)
        XCTAssertEqual(shift?.id, siteA)
        XCTAssertEqual(shift?.start, Fixture.time(7))
        XCTAssertEqual(shift?.end, Fixture.time(16))
        XCTAssertEqual(shift?.breaks.count, 1)
        XCTAssertEqual(shift?.totalBreakMinutes, 30)
        XCTAssertEqual(shift?.jobID, job)
    }

    func testYourOwnOverrideWins() {
        let you = Attendance(memberID: CrewMember.youID, end: Fixture.time(13), breakMinutes: 0)
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay(siteA, present: [you])], on: date)

        XCTAssertEqual(merged?.shifts.first?.end, Fixture.time(13))
        XCTAssertEqual(merged?.shifts.first?.breaks, [])
    }

    func testUntickingYouRemovesIt() {
        let ticked = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay(siteA)], on: date)
        let unticked = SiteCalendarSync.merged(
            personal: ticked,
            siteDays: [siteDay(siteA, present: [Attendance(memberID: UUID())])],
            on: date
        )
        XCTAssertNil(unticked)
    }

    func testManualShiftsAndNoteSurvive() {
        let manual = Shift(start: Fixture.time(18), end: Fixture.time(20))
        let personal = DayRecord(date: date, shifts: [manual], note: "dentist", location: "home", tags: ["x"])
        let merged = SiteCalendarSync.merged(personal: personal, siteDays: [siteDay(siteA)], on: date)

        XCTAssertEqual(merged?.shifts.count, 2)
        XCTAssertEqual(merged?.shifts.first, manual)
        XCTAssertEqual(merged?.shifts.last?.siteID, siteA)
        XCTAssertEqual(merged?.note, "dentist")
        XCTAssertEqual(merged?.location, "home")
        XCTAssertEqual(merged?.tags, ["x"])
    }

    func testTwoSitesSameDayGiveTwoShifts() {
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay(siteA), siteDay(siteB)], on: date)
        XCTAssertEqual(merged?.shifts.compactMap(\.siteID), [siteA, siteB])
    }

    func testDuplicateSiteDaysGiveOneShift() {
        let first = siteDay(siteA)
        var second = siteDay(siteA)
        second.end = Fixture.time(18)
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [first, second], on: date)

        XCTAssertEqual(merged?.shifts.count, 1)
        XCTAssertEqual(merged?.shifts.first?.end, Fixture.time(16))
    }

    func testJobIsTheFrozenOneNotTheSitesCurrent() {
        let frozen = UUID()
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [siteDay(siteA, jobID: frozen)], on: date)
        XCTAssertEqual(merged?.shifts.first?.jobID, frozen)
    }

    func testOnlySiteShiftLeftAndUntickedReturnsNil() {
        let personal = DayRecord(date: date, shifts: [Shift(id: siteA, start: Fixture.time(7), end: Fixture.time(16), siteID: siteA)])
        XCTAssertNil(SiteCalendarSync.merged(personal: personal, siteDays: [], on: date))
    }

    func testSiteDaysOnOtherDatesAreIgnored() {
        let other = siteDay(siteA, date: date.adding(days: 1, in: Fixture.calendar()))
        XCTAssertNil(SiteCalendarSync.merged(personal: nil, siteDays: [other], on: date))
    }

    func testMergingTwiceChangesNothing() {
        let days = [siteDay(siteA), siteDay(siteB)]
        let personal = DayRecord(date: date, shifts: [Shift(start: Fixture.time(18), end: Fixture.time(20))], note: "n")
        let once = SiteCalendarSync.merged(personal: personal, siteDays: days, on: date)
        let twice = SiteCalendarSync.merged(personal: once, siteDays: days, on: date)
        XCTAssertEqual(once, twice)
    }

    func testRebuildDropsShiftForMissingSite() {
        let stale = DayRecord(date: date, shifts: [Shift(id: siteA, start: Fixture.time(7), end: Fixture.time(16), siteID: siteA)])
        let kept = DayRecord(date: date.adding(days: 1, in: Fixture.calendar()), note: "keep")
        let other = siteDay(siteB, date: date.adding(days: 2, in: Fixture.calendar()))

        let rebuilt = SiteCalendarSync.rebuilt(days: [stale, kept], siteDays: [other])

        XCTAssertEqual(rebuilt.map(\.date), [kept.date, other.date])
        XCTAssertEqual(rebuilt.first, kept)
        XCTAssertEqual(rebuilt.last?.shifts.first?.siteID, siteB)
    }

    // MARK: - Shift coding

    func testShiftWithoutSiteIDDecodesFromOldJSON() throws {
        let json = #"{"id":"11111111-1111-4111-8111-111111111111","breaks":[]}"#
        let shift = try JSONDecoder().decode(Shift.self, from: Data(json.utf8))
        XCTAssertNil(shift.siteID)
    }

    func testSiteIDRoundTrips() throws {
        let shift = Shift(start: Fixture.time(7), end: Fixture.time(9), siteID: siteA)
        let decoded = try JSONDecoder().decode(Shift.self, from: JSONEncoder().encode(shift))
        XCTAssertEqual(decoded, shift)
        XCTAssertEqual(decoded.siteID, siteA)
    }

    // MARK: - Calculator warning

    private func siteRecord() -> DayRecord {
        DayRecord(date: date, shifts: [Shift(start: Fixture.time(7), end: Fixture.time(16), siteID: siteA)])
    }

    func testVacationDayWithSiteShiftWarns() {
        var record = siteRecord()
        record.dayTypeID = .vacation
        let result = Fixture.calculator().compute(record: record, on: date)
        XCTAssertTrue(result.warnings.contains(.siteHoursNotCounted))
    }

    func testManualWorkedHoursWithSiteShiftWarns() {
        let settings = Fixture.settings(features: FeatureToggles(autoCalculateWorkedHours: false))
        let result = Fixture.calculator(settings: settings).compute(record: siteRecord(), on: date)
        XCTAssertEqual(result.warnings.filter { $0 == .siteHoursNotCounted }.count, 1)
    }

    func testExcludedDayWithSiteShiftWarns() {
        var record = siteRecord()
        record.isIncluded = false
        let result = Fixture.calculator().compute(record: record, on: date)
        XCTAssertTrue(result.warnings.contains(.siteHoursNotCounted))
    }

    func testPlainWorkDayWithSiteShiftDoesNotWarn() {
        let result = Fixture.calculator().compute(record: siteRecord(), on: date)
        XCTAssertFalse(result.warnings.contains(.siteHoursNotCounted))
    }

    func testVacationDayWithoutSiteShiftDoesNotWarn() {
        let record = Fixture.record(on: date, type: .vacation)
        let result = Fixture.calculator().compute(record: record, on: date)
        XCTAssertFalse(result.warnings.contains(.siteHoursNotCounted))
    }
}
