import XCTest
@testable import Hours

/// A site's work days (1.2): when they are set, the evening reminder nags on
/// exactly those days, and the Sites list says "Today not written yet" only
/// on one of them; a site with the evening reminder or the note on the 1st
/// switched off is left out of that one.
final class SiteWorkDaysTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zagreb")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Thursday 29 October 2026.
    private let thursday = CalendarDate(year: 2026, month: 10, day: 29)
    private let site = UUID()

    // MARK: - Expected today

    func testSetWorkDaysDecideWhetherTheSiteIsExpected() {
        let weekdays = SiteSetup(workDays: [2, 3, 4, 5, 6])
        let weekend = SiteSetup(workDays: [1, 7])

        XCTAssertTrue(SiteWorkDays.expects(site, on: thursday, setup: weekdays, siteDays: [], calendar: calendar))
        XCTAssertFalse(SiteWorkDays.expects(site, on: thursday, setup: weekend, siteDays: [], calendar: calendar))
    }

    /// Without set work days, the weekdays it was worked in the last two
    /// weeks: the evening reminder's own rule.
    func testWithoutWorkDaysTheRecentWeekdaysCount() {
        let lastThursday = SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 22))
        let lastFriday = SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 23))

        XCTAssertTrue(SiteWorkDays.expects(site, on: thursday, setup: SiteSetup(), siteDays: [lastThursday], calendar: calendar))
        XCTAssertFalse(SiteWorkDays.expects(site, on: thursday, setup: SiteSetup(), siteDays: [lastFriday], calendar: calendar))
        XCTAssertFalse(SiteWorkDays.expects(site, on: thursday, setup: SiteSetup(), siteDays: [], calendar: calendar))
    }

    func testAPublicHolidayIsNeverExpected() {
        XCTAssertFalse(SiteWorkDays.expects(
            site, on: thursday, setup: SiteSetup(workDays: [5]), siteDays: [],
            calendar: calendar, holidays: [thursday.key]
        ))
    }

    func testTheWeekdaysAWorkDayListSpells() {
        XCTAssertEqual(SiteWorkDays.inferred(siteID: site, siteDays: [
            SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 26)),
            SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 27)),
            SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 10)),
        ], before: thursday, calendar: calendar), [2, 3], "Monday and Tuesday; the 10th is too long ago")
    }

    // MARK: - Saying which days

    /// "Mon–Fri" and "Mon–Wed, Sat": runs in the week's own order.
    func testWorkDaysAreReadAsRunsInTheWeeksOrder() {
        XCTAssertEqual(SiteWorkDays.runs([2, 3, 4, 5, 6], firstWeekday: 2), [[2, 3, 4, 5, 6]])
        XCTAssertEqual(SiteWorkDays.runs([2, 3, 4, 7], firstWeekday: 2), [[2, 3, 4], [7]])
        // Saturday and Sunday run together in a week that starts on Monday…
        XCTAssertEqual(SiteWorkDays.runs([7, 1], firstWeekday: 2), [[7, 1]])
        // …and not in one that starts on Sunday.
        XCTAssertEqual(SiteWorkDays.runs([7, 1], firstWeekday: 1), [[1], [7]])
        XCTAssertEqual(SiteWorkDays.runs([], firstWeekday: 2), [])
    }

    // MARK: - The evening reminder

    /// A brand-new site with work days but no days yet is nagged about on
    /// its work days.
    func testANewSiteWithWorkDaysIsRemindedOnThem() {
        let dates = SiteReminderPlan.dates(
            siteDays: [],
            today: thursday,
            calendar: calendar,
            daysAhead: 4,
            workDays: [site: [5, 6]]
        )

        XCTAssertEqual(dates, [thursday, CalendarDate(year: 2026, month: 10, day: 30)])
    }

    /// Set work days replace what the history says.
    func testWorkDaysReplaceTheWeekdaysFromHistory() {
        let lastSaturday = SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 24))

        let dates = SiteReminderPlan.dates(
            siteDays: [lastSaturday],
            today: thursday,
            calendar: calendar,
            daysAhead: 3,
            workDays: [site: [5]]
        )

        XCTAssertEqual(dates, [thursday], "Saturday is not one of its work days any more")
    }

    func testASiteWithTheEveningReminderOffIsLeftOut() {
        let lastThursday = SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 22))

        let dates = SiteReminderPlan.dates(
            siteDays: [lastThursday],
            today: thursday,
            calendar: calendar,
            daysAhead: 1,
            workDays: [site: [5]],
            silenced: [site]
        )

        XCTAssertEqual(dates, [])
    }

    func testWithoutWorkDaysOrSilencedSitesNothingChanges() {
        let lastThursday = SiteDay(siteID: site, date: CalendarDate(year: 2026, month: 10, day: 22))

        XCTAssertEqual(
            SiteReminderPlan.dates(siteDays: [lastThursday], today: thursday, calendar: calendar, daysAhead: 1),
            [thursday]
        )
    }

    // MARK: - The note on the 1st

    func testASiteWithTheSheetNoteOffGetsNoNote() {
        let quiet = Site(name: "Quiet")
        let loud = Site(name: "Loud")
        let days = [
            SiteDay(siteID: quiet.id, date: CalendarDate(year: 2026, month: 10, day: 5)),
            SiteDay(siteID: loud.id, date: CalendarDate(year: 2026, month: 10, day: 5)),
        ]

        let reminders = MonthlySheetReminderPlan.reminders(
            sites: [quiet, loud], siteDays: days, today: thursday,
            now: TimeOfDay(hour: 12, minute: 0), time: TimeOfDay(hour: 9, minute: 0),
            silenced: [quiet.id]
        )

        XCTAssertEqual(reminders.map(\.siteName), ["Loud"])
    }
}
