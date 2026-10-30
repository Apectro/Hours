import XCTest
@testable import Hours

/// The export and extra-work screens' small rules (1.2 redesign): which month
/// to offer closing after a sheet is sent, which days a merged crew sheet
/// has nothing written for, last week for the extra-work report, and a
/// report's time in total.
final class ExportScreenRulesTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Thursday 29 October 2026.
    private let today = Fixture.date(2026, 10, 29)
    private let september = YearMonth(year: 2026, month: 9)

    // MARK: - Closing the month after sending

    func testSendingLastMonthOffersClosingIt() {
        XCTAssertEqual(ExportCloseOffer.month(sent: september, today: today, lock: MonthLock()), september)
    }

    func testAMonthAlreadyClosedIsNotOfferedAgain() {
        XCTAssertNil(ExportCloseOffer.month(sent: september, today: today, lock: MonthLock(months: [september])))
    }

    /// Only the month just gone: this month is still running, and an older
    /// one is a correction rather than the monthly sheet.
    func testOnlyThePreviousMonthIsOffered() {
        XCTAssertNil(ExportCloseOffer.month(sent: YearMonth(year: 2026, month: 10), today: today, lock: MonthLock()))
        XCTAssertNil(ExportCloseOffer.month(sent: YearMonth(year: 2026, month: 8), today: today, lock: MonthLock()))
        XCTAssertNil(ExportCloseOffer.month(sent: nil, today: today, lock: MonthLock()))
    }

    /// January offers December of the year before.
    func testTheYearTurnsOver() {
        let december = YearMonth(year: 2025, month: 12)
        XCTAssertEqual(ExportCloseOffer.month(sent: december, today: Fixture.date(2026, 1, 3), lock: MonthLock()), december)
    }

    func testAWholeMonthRangeIsThatMonth() {
        let range = september.range(in: calendar)
        XCTAssertEqual(ExportCloseOffer.wholeMonth(range, calendar: calendar), september)
    }

    func testAPartOfAMonthOrTwoMonthsIsNoMonth() {
        XCTAssertNil(ExportCloseOffer.wholeMonth(
            CalendarDateRange(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 9, 29)), calendar: calendar))
        XCTAssertNil(ExportCloseOffer.wholeMonth(
            CalendarDateRange(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 31)), calendar: calendar))
        XCTAssertNil(ExportCloseOffer.wholeMonth(
            CalendarDateRange(start: Fixture.date(2026, 9, 2), end: Fixture.date(2026, 9, 30)), calendar: calendar))
    }

    // MARK: - Nothing written on a merged sheet

    private let first = Fixture.date(2026, 10, 5)
    private let second = Fixture.date(2026, 10, 6)
    private let third = Fixture.date(2026, 10, 7)

    func testOneSitesMissingDaysAreTheSheets() {
        let site: [CalendarDate: SiteDayStatus] = [first: .missing, second: .written, third: .missing]
        XCTAssertEqual(SiteDayStatus.missingDays(merging: [site]), [first, third])
    }

    /// The crew was on the other site that day: written there, so the
    /// merged sheet has the day.
    func testADayWrittenOnAnotherSiteOfTheSheetIsNotMissing() {
        let trg: [CalendarDate: SiteDayStatus] = [first: .missing, second: .missing]
        let jarun: [CalendarDate: SiteDayStatus] = [first: .written, second: .dayOff]
        XCTAssertEqual(SiteDayStatus.missingDays(merging: [trg, jarun]), [second])
    }

    func testAPartlyWrittenDayCountsAsWritten() {
        let trg: [CalendarDate: SiteDayStatus] = [first: .missing]
        let jarun: [CalendarDate: SiteDayStatus] = [first: .partly]
        XCTAssertEqual(SiteDayStatus.missingDays(merging: [trg, jarun]), [])
    }

    func testNoSitesNoMissingDays() {
        XCTAssertEqual(SiteDayStatus.missingDays(merging: []), [])
    }

    // MARK: - Last week, for the extra-work report

    func testLastWeekIsTheWholeWeekBeforeThisOne() {
        let thisWeek = CalendarDateRange.week(containing: today, in: calendar)
        guard case let .dates(range) = ExtraWorkRange.lastWeek(today: today, calendar: calendar) else {
            return XCTFail("last week is a range of dates")
        }
        XCTAssertEqual(range.end, thisWeek.start.adding(days: -1, in: calendar))
        XCTAssertEqual(range.start, thisWeek.start.adding(days: -7, in: calendar))
    }

    // MARK: - A report's time

    private func job(_ minutes: [Int], done: Bool = true) -> ExtraWorkJob {
        var job = ExtraWorkJob(siteID: UUID(), date: today, isDone: done)
        job.hours = minutes.map { ExtraWorkHours(memberID: UUID(), name: "", minutes: $0) }
        return job
    }

    /// Each job counts as long as it took, however many were on it.
    func testAReportsTimeAddsUpEachJobOnce() {
        XCTAssertEqual(ExtraWorkReport.totalMinutes(of: [job([150, 150]), job([75]), job([])]), 225)
        XCTAssertEqual(ExtraWorkReport.totalMinutes(of: []), 0)
    }
}
