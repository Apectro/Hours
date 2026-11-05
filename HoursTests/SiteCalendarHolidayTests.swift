import XCTest
@testable import Hours

/// A site's month grid against the personal calendar (2026-11-05, "on the
/// sites calendar holidays aren't shown"): public holidays read as holidays,
/// on this month's days and the neighbours', a written holiday keeps a mark;
/// a paused site's days read as paused; days before the site's first day and
/// after an archived site's last are not missing; a no-work day adds nothing
/// to its week; the month's heading names the year away from this one.
final class SiteCalendarHolidayTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let site = UUID()
    private let setup = SiteSetup(workDays: [2, 3, 4, 5, 6])

    /// November 2026: Monday 26 October to Sunday 6 December.
    private func november() -> MonthLayout {
        MonthLayout.make(month: YearMonth(year: 2026, month: 11), calendar: calendar, includesWeekends: true)
    }

    private func day(_ date: CalendarDate, _ people: [UUID] = [CrewMember.youID]) -> SiteDay {
        SiteDay(
            siteID: site,
            date: date,
            start: Fixture.time(7),
            end: Fixture.time(15),
            breakMinutes: 0,
            present: people.map { Attendance(memberID: $0) }
        )
    }

    /// All Saints' Day, 1 November, and the Day of Remembrance, 18
    /// November; Christmas on 25 December, in the next month; and a
    /// "working holiday" on 4 November that is no day off.
    private func rules() -> [HolidayRule] {
        [
            HolidayRule(name: "All Saints' Day", recurrence: .annual(month: 11, day: 1)),
            HolidayRule(name: "Remembrance Day", recurrence: .annual(month: 11, day: 18)),
            HolidayRule(name: "Christmas Day", recurrence: .annual(month: 12, day: 25)),
            HolidayRule(name: "Shop day", recurrence: .annual(month: 11, day: 4), countsAsWorkingDay: true),
            HolidayRule(name: "Reformation Day", recurrence: .annual(month: 10, day: 31))
        ]
    }

    private func holidays() -> [CalendarDate: String] {
        let range = SiteCalendarGrid.fetchRange(of: november(), calendar: calendar)
        return HolidayResolver(rules: rules(), calendar: calendar, covering: range).daysOff(in: range, calendar: calendar)
    }

    private func looks(
        _ days: [SiteDay],
        setup: SiteSetup? = nil,
        today: CalendarDate = Fixture.date(2026, 11, 20),
        active: SiteActiveDays = .always
    ) -> [CalendarDate: SiteCalendarDayLook] {
        let setup = setup ?? self.setup
        let names = holidays()
        let statuses = SiteCalendarGrid.statuses(
            layout: november(),
            siteID: site,
            siteDays: days,
            members: [],
            setup: setup,
            today: today,
            calendar: calendar,
            holidays: Set(names.keys.map(\.key)),
            active: active
        )
        return SiteCalendarGrid.looks(
            layout: november(),
            statuses: statuses,
            holidays: names,
            siteID: site,
            siteDays: days,
            setup: setup,
            today: today,
            calendar: calendar,
            active: active
        )
    }

    // MARK: - The holidays

    func testTheHolidaysOffAreNamedAndAWorkingHolidayIsNot() {
        let names = holidays()

        XCTAssertEqual(names[Fixture.date(2026, 11, 1)], "All Saints' Day")
        XCTAssertEqual(names[Fixture.date(2026, 11, 18)], "Remembrance Day")
        XCTAssertNil(names[Fixture.date(2026, 11, 4)], "a holiday that counts as a working day is no day off")
    }

    func testTheHolidaysCoverTheWholeGridTheNeighboursToo() {
        let names = holidays()

        XCTAssertEqual(names[Fixture.date(2026, 10, 31)], "Reformation Day", "a day of October in the first row")
        XCTAssertNil(names[Fixture.date(2026, 12, 25)], "past the grid's last row")
    }

    func testAHolidayIsDrawnAsAHolidayWithItsName() {
        let result = looks([])

        let wednesday = result[Fixture.date(2026, 11, 18)]
        XCTAssertEqual(wednesday?.kind, .holiday, "a work day that is a public holiday")
        XCTAssertEqual(wednesday?.holidayName, "Remembrance Day")
        XCTAssertEqual(wednesday?.hasTile, true, "on a tile, as the personal calendar draws it")
        XCTAssertEqual(wednesday?.hasHolidayMark, false, "the tile says it already")
        XCTAssertEqual(result[Fixture.date(2026, 11, 1)]?.kind, .holiday, "a Sunday that is a public holiday")
        XCTAssertEqual(result[Fixture.date(2026, 11, 4)]?.kind, .missing, "a working holiday is an ordinary work day")
    }

    func testANeighbourMonthsHolidayIsDrawnAsAHoliday() {
        let result = looks([])

        XCTAssertEqual(result[Fixture.date(2026, 10, 31)]?.kind, .holiday)
        XCTAssertEqual(result[Fixture.date(2026, 10, 31)]?.holidayName, "Reformation Day")
    }

    func testAWrittenHolidayIsWrittenAndKeepsAMark() {
        let result = looks([day(Fixture.date(2026, 11, 18))])

        let look = result[Fixture.date(2026, 11, 18)]
        XCTAssertEqual(look?.kind, .written)
        XCTAssertEqual(look?.holidayName, "Remembrance Day")
        XCTAssertEqual(look?.hasHolidayMark, true)
        XCTAssertEqual(look?.hasTile, true)
    }

    func testAHolidayToComeIsAHolidayNotADayToCome() {
        let result = looks([], today: Fixture.date(2026, 11, 10))

        XCTAssertEqual(result[Fixture.date(2026, 11, 18)]?.kind, .holiday)
        XCTAssertEqual(result[Fixture.date(2026, 11, 19)]?.kind, .future)
    }

    func testAHolidayRowIsNotShort() {
        // Today in October: November's last row, 30 November to 6
        // December, is all to come; its second-to-last has the holiday.
        let today = Fixture.date(2026, 10, 1)
        let result = looks([], today: today)

        let short = SiteCalendarGrid.shortRows(of: november(), looks: result, today: today)

        XCTAssertEqual(short[3], false, "the row with the 18th")
        XCTAssertEqual(short[5], true)
    }

    // MARK: - The other kinds

    func testEveryStatusHasItsOwnKind() {
        let noWork = SiteDay.noWork(.noWork, siteID: site, date: Fixture.date(2026, 11, 3), jobID: nil)
        let result = looks([day(Fixture.date(2026, 11, 2)), noWork])

        XCTAssertEqual(result[Fixture.date(2026, 11, 2)]?.kind, .written)
        XCTAssertEqual(result[Fixture.date(2026, 11, 3)]?.kind, .noWork)
        XCTAssertEqual(result[Fixture.date(2026, 11, 5)]?.kind, .missing)
        XCTAssertEqual(result[Fixture.date(2026, 11, 7)]?.kind, .dayOff, "a Saturday")
        XCTAssertEqual(result[Fixture.date(2026, 11, 23)]?.kind, .future)
        XCTAssertFalse(result[Fixture.date(2026, 11, 3)]?.hasTile ?? true)
        XCTAssertFalse(result[Fixture.date(2026, 11, 7)]?.hasTile ?? true)
    }

    func testAPausedSitesWorkDaysArePausedAndItsWeekendsDaysOff() {
        var paused = setup
        paused.pause = SitePause(start: Fixture.date(2026, 11, 9), end: Fixture.date(2026, 11, 22))
        let result = looks([day(Fixture.date(2026, 11, 2))], setup: paused)

        XCTAssertEqual(result[Fixture.date(2026, 11, 10)]?.kind, .paused)
        XCTAssertEqual(result[Fixture.date(2026, 11, 14)]?.kind, .dayOff, "a Saturday in the pause")
        XCTAssertEqual(result[Fixture.date(2026, 11, 18)]?.kind, .holiday, "a holiday in the pause is a holiday")
        XCTAssertEqual(result[Fixture.date(2026, 11, 6)]?.kind, .missing, "before the pause")
        XCTAssertFalse(result[Fixture.date(2026, 11, 10)]?.hasTile ?? true)
    }

    // MARK: - The site's own span

    func testDaysBeforeTheSitesFirstDayAreNotMissing() {
        let first = Fixture.date(2026, 11, 11)
        let active = SiteActiveDays.of(
            firstWritten: first, lastWritten: first, isArchived: false, today: Fixture.date(2026, 11, 20), calendar: calendar
        )
        let result = looks([day(first)], active: active)

        XCTAssertEqual(result[Fixture.date(2026, 11, 10)]?.kind, .dayOff, "the day before the first")
        XCTAssertEqual(result[Fixture.date(2026, 10, 27)]?.kind, .dayOff, "October, before the site")
        XCTAssertEqual(result[Fixture.date(2026, 11, 12)]?.kind, .missing, "after the first day")
        XCTAssertEqual(result[Fixture.date(2026, 11, 11)]?.kind, .written)
    }

    func testANewSiteWithNothingWrittenHasNothingMissingYetButItsDaysToCome() {
        let today = Fixture.date(2026, 11, 20)
        let active = SiteActiveDays.of(firstWritten: nil, lastWritten: nil, isArchived: false, today: today, calendar: calendar)
        let result = looks([], active: active)

        XCTAssertEqual(result[Fixture.date(2026, 11, 19)]?.kind, .dayOff)
        XCTAssertEqual(result[Fixture.date(2026, 11, 20)]?.kind, .future, "today")
        XCTAssertEqual(result[Fixture.date(2026, 11, 23)]?.kind, .future)
    }

    func testAFirstDayStillToComeLeavesTheDaysUpToTodayAsTheyWere() {
        let today = Fixture.date(2026, 11, 20)
        let first = Fixture.date(2026, 11, 25)
        let active = SiteActiveDays.of(firstWritten: first, lastWritten: first, isArchived: false, today: today, calendar: calendar)

        XCTAssertEqual(active.since, today)
        XCTAssertTrue(active.contains(Fixture.date(2026, 11, 23)))
        XCTAssertFalse(active.contains(Fixture.date(2026, 11, 19)))
    }

    func testAnArchivedSiteExpectsNothingAfterItsLastDay() {
        let today = Fixture.date(2026, 11, 20)
        let active = SiteActiveDays.of(
            firstWritten: Fixture.date(2026, 11, 2), lastWritten: Fixture.date(2026, 11, 6),
            isArchived: true, today: today, calendar: calendar
        )
        let result = looks([day(Fixture.date(2026, 11, 2)), day(Fixture.date(2026, 11, 6))], active: active)

        XCTAssertEqual(result[Fixture.date(2026, 11, 3)]?.kind, .missing, "inside its time")
        XCTAssertEqual(result[Fixture.date(2026, 11, 9)]?.kind, .dayOff, "after its last day")
        XCTAssertEqual(result[Fixture.date(2026, 11, 23)]?.kind, .dayOff, "no day to come")
    }

    func testAnArchivedSiteWithNothingWrittenExpectsNothing() {
        let today = Fixture.date(2026, 11, 20)
        let active = SiteActiveDays.of(firstWritten: nil, lastWritten: nil, isArchived: true, today: today, calendar: calendar)
        let result = looks([], active: active)

        XCTAssertFalse(result.values.contains { $0.kind == .missing || $0.kind == .future })
    }

    func testTheMissingCountMatchesTheRedDays() {
        let first = Fixture.date(2026, 11, 11)
        let today = Fixture.date(2026, 11, 20)
        let active = SiteActiveDays.of(firstWritten: first, lastWritten: first, isArchived: false, today: today, calendar: calendar)
        let statuses = SiteCalendarGrid.statuses(
            layout: november(), siteID: site, siteDays: [day(first)], members: [], setup: setup,
            today: today, calendar: calendar, holidays: Set(holidays().keys.map(\.key)), active: active
        )

        let month = YearMonth(year: 2026, month: 11)
        let count = SiteDayStatus.missingCount(in: statuses.filter { month.contains($0.key) })

        // 12, 13, 16, 17, 19: the 18th is a holiday, the 20th today.
        XCTAssertEqual(count, 5)
    }

    // MARK: - Week totals

    func testANoWorkDayAddsNothingToItsWeek() {
        var rained = day(Fixture.date(2026, 11, 3), [CrewMember.youID])
        rained.noWork = .noWork
        rained.present = []
        let weather = SiteDay.noWork(
            .badWeather, siteID: site, date: Fixture.date(2026, 11, 4), jobID: nil, usual: day(Fixture.date(2026, 11, 4))
        )
        let calculator = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)

        let totals = SiteCalendarGrid.weekMinutes(
            of: november(), siteID: site, siteDays: [day(Fixture.date(2026, 11, 2)), rained, weather],
            calculator: calculator, calendar: calendar
        )

        XCTAssertEqual(totals[1], 480)
    }

    // MARK: - The month's heading

    func testTheHeadingNamesTheYearOnlyAwayFromThisOne() {
        let formatting = CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)
        let today = Fixture.date(2027, 1, 12)

        XCTAssertEqual(formatting.monthHeading(YearMonth(year: 2027, month: 1), today: today), "January")
        XCTAssertEqual(formatting.monthHeading(YearMonth(year: 2026, month: 12), today: today), "December 2026")
    }
}
