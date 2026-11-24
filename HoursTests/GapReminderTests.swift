import XCTest
@testable import Hours

/// Finding days with nothing recorded.
final class GapReminderTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let today = Fixture.date(2026, 8, 14)

    private func days(records: [Int: DayRecord], holidays: [HolidayRule] = []) -> [DayComputation] {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 14))
        return Fixture.engine(calendar: calendar).days(in: range, records: records, holidays: holidays)
    }

    func testAWorkingDayWithNothingOnItIsAGap() {
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:]), asOf: today)

        // Monday 3rd to Thursday 13th: nine working days before today.
        XCTAssertEqual(gaps.count, 9)
        XCTAssertTrue(gaps.contains(Fixture.workingMonday))
        XCTAssertFalse(gaps.contains(today), "today is not over yet")
    }

    func testWeekendsAreNeverGaps() {
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 8)))
        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 9)))
    }

    func testARecordedDayIsNotAGap() {
        let worked = DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16))
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [worked.date.key: worked]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
        XCTAssertEqual(gaps.count, 8)
    }

    /// Hours that came from a site day are hours: the weekly reminder does
    /// not count that day as unrecorded.
    func testADayWrittenOnASiteIsNotAGap() throws {
        let site = UUID()
        let siteDay = SiteDay(
            siteID: site, date: Fixture.workingMonday, start: Fixture.time(7), end: Fixture.time(15),
            present: [Attendance(memberID: CrewMember.youID)]
        )
        let record = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [siteDay], on: siteDay.date))
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [record.date.key: record]), asOf: today)
        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
        XCTAssertEqual(gaps.count, 8)
    }

    /// Away from the site for a reason is written too; a site day you were
    /// simply not on leaves your own day as it was.
    func testAwayFromTheSiteForAReasonIsNotAGapButNotBeingOnItIs() throws {
        let site = UUID()
        let sick = SiteDay(
            siteID: site, date: Fixture.workingMonday, start: Fixture.time(7), end: Fixture.time(15),
            present: [], absences: [CrewAbsence(memberID: CrewMember.youID, dayTypeID: .sick)]
        )
        let record = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [sick], on: sick.date))
        XCTAssertFalse(
            GapFinder.unrecordedWorkingDays(in: days(records: [record.date.key: record]), asOf: today)
                .contains(Fixture.workingMonday)
        )
        let withoutYou = SiteDay(
            siteID: site, date: Fixture.workingTuesday, start: Fixture.time(7), end: Fixture.time(15),
            present: [Attendance(memberID: UUID())]
        )
        XCTAssertNil(SiteCalendarSync.merged(personal: nil, siteDays: [withoutYou], on: withoutYou.date))
    }

    func testADayOfLeaveIsNotAGap() {
        let leave = DayRecord(date: Fixture.workingMonday, dayTypeID: .vacation)
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [leave.date.key: leave]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
    }

    func testAPublicHolidayIsNotAGap() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 5))
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [:], holidays: [holiday]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.date(2026, 8, 5)))
    }

    func testAnExcludedDayIsNotAGap() {
        var excluded = DayRecord(date: Fixture.workingMonday)
        excluded.isIncluded = false
        let gaps = GapFinder.unrecordedWorkingDays(in: days(records: [excluded.date.key: excluded]), asOf: today)

        XCTAssertFalse(gaps.contains(Fixture.workingMonday))
    }

    // MARK: - The window

    func testTheWindowEndsYesterday() {
        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)

        XCTAssertEqual(window.end, Fixture.date(2026, 8, 13))
        XCTAssertEqual(window.start, Fixture.date(2026, 7, 31))
        XCTAssertFalse(window.contains(today))
    }
}
