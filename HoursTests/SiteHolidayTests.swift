import XCTest
@testable import Hours

/// A public holiday is not a site day anyone forgot to write.
final class SiteHolidayTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Tuesday 2026-10-20.
    private let today = Fixture.date(2026, 10, 20)
    private let site = UUID()

    func testNoEveningReminderOnAPublicHoliday() {
        // Worked Mondays; Monday 26 October is Austria's National Day.
        let days = [SiteDay(siteID: site, date: Fixture.date(2026, 10, 12))]
        let nationalDay = Fixture.date(2026, 10, 26)

        XCTAssertEqual(SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar), [nationalDay])
        XCTAssertEqual(
            SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar, holidays: [nationalDay.key]),
            []
        )
    }

    func testAPublicHolidayIsNotOutlinedAsUnwritten() {
        let monday = Fixture.date(2026, 10, 12)
        XCTAssertTrue(SiteUnwrittenDay.isUnwritten(monday, isInMonth: true, today: today, isWritten: false,
                                                   calendar: calendar))
        XCTAssertFalse(SiteUnwrittenDay.isUnwritten(monday, isInMonth: true, today: today, isWritten: false,
                                                    calendar: calendar, holidays: [monday.key]))
    }

    func testTheRestOfTheRuleIsUnchanged() {
        let saturday = Fixture.date(2026, 10, 17)
        let monday = Fixture.date(2026, 10, 12)
        XCTAssertFalse(SiteUnwrittenDay.isUnwritten(saturday, isInMonth: true, today: today, isWritten: false,
                                                    calendar: calendar), "weekend")
        XCTAssertFalse(SiteUnwrittenDay.isUnwritten(monday, isInMonth: true, today: today, isWritten: true,
                                                    calendar: calendar), "written")
        XCTAssertFalse(SiteUnwrittenDay.isUnwritten(today, isInMonth: true, today: today, isWritten: false,
                                                    calendar: calendar), "today is not over")
        XCTAssertFalse(SiteUnwrittenDay.isUnwritten(monday, isInMonth: false, today: today, isWritten: false,
                                                    calendar: calendar), "another month")
    }

    func testOnlyHolidaysThatAreDaysOffCount() {
        let rules = [
            HolidayRule(name: "Nationalfeiertag", recurrence: .annual(month: 10, day: 26)),
            HolidayRule(name: "Betriebstag", recurrence: .annual(month: 10, day: 27), countsAsWorkingDay: true),
            HolidayRule(name: "Aus", recurrence: .annual(month: 10, day: 28), isEnabled: false),
        ]
        let range = CalendarDateRange(start: Fixture.date(2026, 10, 20), end: Fixture.date(2026, 10, 31))
        let resolver = HolidayResolver(rules: rules, calendar: calendar, covering: range)
        XCTAssertEqual(resolver.daysOffKeys(in: range, calendar: calendar), [Fixture.date(2026, 10, 26).key])
    }
}
