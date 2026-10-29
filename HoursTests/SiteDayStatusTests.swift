import XCTest
@testable import Hours

/// How each day of a site reads in its month: written, partly written,
/// missing, a day off or still to come.
final class SiteDayStatusTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Tuesday 20 October 2026.
    private let today = Fixture.date(2026, 10, 20)
    private let site = UUID()
    private let ana = UUID()
    private let ivo = UUID()
    private let weekdays: Set<Int> = [2, 3, 4, 5, 6]

    private var setup: SiteSetup { SiteSetup(workDays: weekdays) }

    private func status(
        _ date: CalendarDate,
        siteDays: [SiteDay] = [],
        setup: SiteSetup? = nil,
        crew: Set<UUID> = [],
        holidays: Set<Int> = []
    ) -> SiteDayStatus {
        SiteDayStatus.of(
            siteID: site,
            on: date,
            siteDays: siteDays,
            setup: setup ?? self.setup,
            crew: crew,
            today: today,
            calendar: calendar,
            holidays: holidays
        )
    }

    func testAPastWorkDayWithNoSiteDayIsMissing() {
        XCTAssertEqual(status(Fixture.date(2026, 10, 19)), .missing)
    }

    func testAWrittenDayIsWritten() {
        let monday = Fixture.date(2026, 10, 19)
        let day = SiteDay(siteID: site, date: monday, present: [Attendance(memberID: ana), Attendance(memberID: ivo)])

        XCTAssertEqual(status(monday, siteDays: [day], crew: [ana, ivo]), .written)
    }

    func testAnotherSitesDayDoesNotWriteThisOne() {
        let monday = Fixture.date(2026, 10, 19)
        let elsewhere = SiteDay(siteID: UUID(), date: monday, present: [Attendance(memberID: ana)])

        XCTAssertEqual(status(monday, siteDays: [elsewhere]), .missing)
    }

    func testSomeoneNeitherTickedNorAwayMakesItPartly() {
        let monday = Fixture.date(2026, 10, 19)
        let day = SiteDay(siteID: site, date: monday, present: [Attendance(memberID: ana)])

        XCTAssertEqual(status(monday, siteDays: [day], crew: [ana, ivo]), .partly)
    }

    func testSomeoneAwayForAReasonIsAccountedFor() {
        let monday = Fixture.date(2026, 10, 19)
        let day = SiteDay(siteID: site, date: monday, present: [Attendance(memberID: ana)])
            .settingAbsence(.sick, for: ivo)

        XCTAssertEqual(status(monday, siteDays: [day], crew: [ana, ivo]), .written)
    }

    func testAWorkDayOfTheSiteNotWorkedIsADayOff() {
        let saturday = Fixture.date(2026, 10, 17)
        XCTAssertEqual(status(saturday), .dayOff)

        let mondaysOnly = SiteSetup(workDays: [2])
        XCTAssertEqual(status(Fixture.date(2026, 10, 14), setup: mondaysOnly), .dayOff, "a Wednesday")
        XCTAssertEqual(status(Fixture.date(2026, 10, 12), setup: mondaysOnly), .missing, "a Monday")
    }

    func testAPublicHolidayIsADayOff() {
        let monday = Fixture.date(2026, 10, 19)
        XCTAssertEqual(status(monday, holidays: [monday.key]), .dayOff)
    }

    func testTodayAndLaterAreStillToCome() {
        XCTAssertEqual(status(today), .future, "today is not over yet")
        XCTAssertEqual(status(Fixture.date(2026, 10, 21)), .future)
        XCTAssertEqual(status(Fixture.date(2026, 10, 24)), .dayOff, "a Saturday to come is still a day off")
    }

    func testTodayWrittenIsWritten() {
        let day = SiteDay(siteID: site, date: today, present: [Attendance(memberID: ana)])
        XCTAssertEqual(status(today, siteDays: [day], crew: [ana]), .written)
    }

    func testWithoutWorkDaysTheSiteGoesByTheDaysItWasWorkedLately() {
        // Worked on Monday 12th only: Monday 19th is expected, Tuesday 13th
        // and Friday 16th are not.
        let worked = SiteDay(siteID: site, date: Fixture.date(2026, 10, 12), present: [Attendance(memberID: ana)])
        let open = SiteSetup()

        XCTAssertEqual(status(Fixture.date(2026, 10, 19), siteDays: [worked], setup: open), .missing)
        XCTAssertEqual(status(Fixture.date(2026, 10, 16), siteDays: [worked], setup: open), .dayOff)
    }

    func testTheMonthAndItsMissingCount() {
        let monday = Fixture.date(2026, 10, 19)
        let days = [
            SiteDay(siteID: site, date: monday, present: [Attendance(memberID: ana)]),
            SiteDay(siteID: site, date: Fixture.date(2026, 10, 16), present: [Attendance(memberID: ana), Attendance(memberID: ivo)]),
        ]
        let month = SiteDayStatus.month(
            YearMonth(year: 2026, month: 10),
            siteID: site,
            siteDays: days,
            setup: setup,
            crew: [ana, ivo],
            today: today,
            calendar: calendar,
            holidays: [Fixture.date(2026, 10, 8).key]
        )

        XCTAssertEqual(month.count, 31)
        XCTAssertEqual(month[monday], .partly)
        XCTAssertEqual(month[Fixture.date(2026, 10, 16)], .written)
        XCTAssertEqual(month[Fixture.date(2026, 10, 8)], .dayOff)
        XCTAssertEqual(month[today], .future)
        // October 1–19 has 13 weekdays; two are written, one a holiday.
        XCTAssertEqual(SiteDayStatus.missingCount(in: month), 10)
    }
}
