import XCTest
@testable import Hours

final class SiteReminderPlanTests: XCTestCase {
    private let calendar = Fixture.calendar()
    // Tuesday 2026-10-20.
    private let today = Fixture.date(2026, 10, 20)
    private let siteA = UUID()
    private let siteB = UUID()

    private func day(_ site: UUID, _ date: CalendarDate) -> SiteDay {
        SiteDay(siteID: site, date: date)
    }

    private func plan(_ days: [SiteDay]) -> [CalendarDate] {
        SiteReminderPlan.dates(siteDays: days, today: today, calendar: calendar)
    }

    func testNoRecentSiteWorkNoReminders() {
        XCTAssertEqual(plan([]), [])
        // 15 days back is outside the 14-day window.
        XCTAssertEqual(plan([day(siteA, today.adding(days: -15, in: calendar))]), [])
        // Today itself is not history.
        XCTAssertEqual(plan([day(siteA, today)]), [])
    }

    func testOnlyWeekdaysThatWereWorked() {
        // Monday 12th and Wednesday 14th.
        let result = plan([day(siteA, Fixture.date(2026, 10, 12)), day(siteA, Fixture.date(2026, 10, 14))])
        XCTAssertEqual(result, [Fixture.date(2026, 10, 21), Fixture.date(2026, 10, 26)])
    }

    func testTodayAlreadyRecordedIsSkipped() {
        // Worked last Tuesday (13th); today (Tuesday) is recorded.
        let result = plan([day(siteA, Fixture.date(2026, 10, 13)), day(siteA, today)])
        XCTAssertEqual(result, [])
    }

    func testTwoSitesOnDifferentWeekdaysRemindOnBoth() {
        let result = plan([day(siteA, Fixture.date(2026, 10, 12)), day(siteB, Fixture.date(2026, 10, 14))])
        XCTAssertEqual(result, [Fixture.date(2026, 10, 21), Fixture.date(2026, 10, 26)])
    }

    func testTodayStillReturnedWhenAnotherSiteIsMissing() {
        // Both sites work Tuesdays; only A is recorded today.
        let result = plan([
            day(siteA, Fixture.date(2026, 10, 13)),
            day(siteB, Fixture.date(2026, 10, 13)),
            day(siteA, today)
        ])
        XCTAssertEqual(result, [today])
    }

    func testOldPreferencesDecodeWithDefaults() throws {
        let json = #"{"isEnabled":true,"weekday":5,"time":{"hour":16,"minute":0},"lookBackDays":10}"#
        let prefs = try JSONDecoder().decode(ReminderPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(prefs.siteRemindersEnabled)
        XCTAssertEqual(prefs.siteReminderTime, TimeOfDay(hour: 18, minute: 0))
        XCTAssertEqual(prefs.weekday, 5)
    }
}
