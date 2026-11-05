import XCTest
@testable import Hours

/// A site's month in the Today tab's tile look: the statuses of every day
/// the grid draws (the neighbouring months' too, each judged as its own
/// month would judge it), the people under each written day, the crew's
/// hours on the site in each row's whole week, and the rows with no tile.
final class SiteCalendarGridTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let site = UUID()
    private let ana = UUID()
    private let ivo = UUID()
    private let setup = SiteSetup(workDays: [2, 3, 4, 5, 6])

    /// November 2026: 26 October to 6 December, six rows.
    private func november() -> MonthLayout {
        MonthLayout.make(month: YearMonth(year: 2026, month: 11), calendar: calendar, includesWeekends: true)
    }

    private func day(_ date: CalendarDate, _ people: [UUID], site: UUID? = nil) -> SiteDay {
        SiteDay(
            siteID: site ?? self.site,
            date: date,
            start: Fixture.time(7),
            end: Fixture.time(15),
            breakMinutes: 0,
            present: people.map { Attendance(memberID: $0) }
        )
    }

    private func statuses(_ days: [SiteDay], members: [CrewMember] = [], today: CalendarDate) -> [CalendarDate: SiteDayStatus] {
        SiteCalendarGrid.statuses(
            layout: november(),
            siteID: site,
            siteDays: days,
            members: members,
            setup: setup,
            today: today,
            calendar: calendar,
            holidays: []
        )
    }

    // MARK: - What to fetch

    func testTheFetchCoversTheLookBackBeforeTheFirstMonthAndTheLastRowsWeek() {
        let range = SiteCalendarGrid.fetchRange(of: november(), calendar: calendar)

        XCTAssertEqual(range.start, Fixture.date(2026, 10, 1).adding(days: -SiteWorkDays.lookBackDays, in: calendar))
        XCTAssertEqual(range.end, Fixture.date(2026, 12, 6))
    }

    // MARK: - Statuses

    func testEveryDayOfTheGridHasAStatusTheNeighboursToo() {
        let result = statuses([day(Fixture.date(2026, 10, 27), [CrewMember.youID])], today: Fixture.date(2026, 11, 18))

        XCTAssertEqual(result.count, 42)
        XCTAssertEqual(result[Fixture.date(2026, 10, 27)], .written)
        XCTAssertEqual(result[Fixture.date(2026, 10, 26)], .missing)
        XCTAssertEqual(result[Fixture.date(2026, 11, 1)], .dayOff, "a Sunday")
        XCTAssertEqual(result[Fixture.date(2026, 12, 1)], .future)
    }

    func testTheMonthsOwnDaysReadAsTheMonthAloneWould() {
        let members = [CrewMember(id: ana, siteID: site, name: "Ana"), CrewMember(id: ivo, siteID: site, name: "Ivo")]
        let days = [
            day(Fixture.date(2026, 11, 2), [ana, ivo]),
            day(Fixture.date(2026, 11, 3), [ana]),
            day(Fixture.date(2026, 12, 1), [ana])
        ]
        let today = Fixture.date(2026, 12, 3)
        let range = YearMonth(year: 2026, month: 11).range(in: calendar)
        let alone = SiteDayStatus.month(
            YearMonth(year: 2026, month: 11),
            siteID: site,
            siteDays: days.filter { $0.date <= range.end },
            setup: setup,
            check: SiteMonthOverview.crew(
                siteID: site, members: members, siteDays: days.filter { $0.date <= range.end },
                month: YearMonth(year: 2026, month: 11), calendar: calendar
            ),
            today: today,
            calendar: calendar
        )

        let result = statuses(days, members: members, today: today)

        for (date, status) in alone {
            XCTAssertEqual(result[date], status, "\(date)")
        }
        XCTAssertEqual(result[Fixture.date(2026, 11, 3)], .partly)
    }

    // MARK: - People and hours

    func testUnderAWrittenDayIsHowManyWereOnItYouIncluded() {
        let days = [
            day(Fixture.date(2026, 11, 2), [CrewMember.youID, ana, ivo]),
            day(Fixture.date(2026, 11, 3), [ana]),
            day(Fixture.date(2026, 11, 4), [ana, ivo], site: UUID())
        ]

        let people = SiteCalendarGrid.people(siteID: site, siteDays: days)

        XCTAssertEqual(people[Fixture.date(2026, 11, 2)], 3)
        XCTAssertEqual(people[Fixture.date(2026, 11, 3)], 1)
        XCTAssertNil(people[Fixture.date(2026, 11, 4)], "another site's day")
    }

    func testEachRowsWeekHasTheCrewsHoursOnThisSite() {
        let days = [
            day(Fixture.date(2026, 10, 27), [CrewMember.youID, ana]),
            day(Fixture.date(2026, 11, 3), [ana]),
            day(Fixture.date(2026, 11, 4), [ana], site: UUID()),
            day(Fixture.date(2026, 12, 4), [ivo])
        ]
        let calculator = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)

        let totals = SiteCalendarGrid.weekMinutes(
            of: november(), siteID: site, siteDays: days, calculator: calculator, calendar: calendar
        )

        XCTAssertEqual(totals, [960, 480, 0, 0, 0, 480])
    }

    // MARK: - Tiles and short rows

    func testWrittenPartlyAndMissingDaysHaveATile() {
        func tile(_ status: SiteDayStatus) -> Bool {
            SiteCalendarDayLook.of(status, holidayName: nil, isPaused: false) { false }.hasTile
        }
        XCTAssertTrue(tile(.written))
        XCTAssertTrue(tile(.partly))
        XCTAssertTrue(tile(.missing))
        XCTAssertFalse(tile(.dayOff))
        XCTAssertFalse(tile(.future))
    }

    func testRowsWithNoTileAndNotTodayAreShort() {
        let today = Fixture.date(2026, 11, 18)
        let result = statuses([], today: today)
        let looks = SiteCalendarGrid.looks(
            layout: november(), statuses: result, holidays: [:], siteID: site, siteDays: [],
            setup: setup, today: today, calendar: calendar
        )

        let short = SiteCalendarGrid.shortRows(of: november(), looks: looks, today: today)

        // Rows 0–2 are missed work days, row 3 has today; the rest is to come.
        XCTAssertEqual(short, [false, false, false, false, true, true])
    }
}
