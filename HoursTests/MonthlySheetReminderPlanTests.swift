import XCTest
@testable import Hours

/// The note on the 1st that last month's sheet is ready for the director.
final class MonthlySheetReminderPlanTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let nine = TimeOfDay(hour: 9, minute: 0)
    private let trg = Site(name: "Trg Pravde", sortOrder: 0)
    private let kai = Site(name: "Kaiserstrasse 12", sortOrder: 1)

    private func day(_ site: Site, _ date: CalendarDate) -> SiteDay {
        SiteDay(siteID: site.id, date: date)
    }

    private func plan(
        sites: [Site],
        days: [SiteDay],
        today: CalendarDate,
        now: TimeOfDay = TimeOfDay(hour: 12, minute: 0)
    ) -> [MonthlySheetReminder] {
        MonthlySheetReminderPlan.reminders(
            sites: sites,
            siteDays: days,
            today: today,
            now: now,
            time: nine
        )
    }

    func testOnTheFirstOfNextMonthForASiteWorkedThisMonth() {
        let result = plan(sites: [trg], days: [day(trg, Fixture.date(2026, 10, 14))], today: Fixture.date(2026, 10, 21))

        XCTAssertEqual(result, [
            MonthlySheetReminder(
                siteID: trg.id,
                siteName: "Trg Pravde",
                month: YearMonth(year: 2026, month: 10),
                date: Fixture.date(2026, 11, 1)
            )
        ])
    }

    func testOneReminderPerSiteInTheSitesOrder() {
        let days = [day(kai, Fixture.date(2026, 10, 2)), day(trg, Fixture.date(2026, 10, 3)), day(kai, Fixture.date(2026, 10, 5))]

        let result = plan(sites: [trg, kai], days: days, today: Fixture.date(2026, 10, 21))

        XCTAssertEqual(result.map(\.siteID), [trg.id, kai.id])
    }

    /// Nothing written on a site this month means there is no sheet to send.
    func testASiteWithNoDaysInTheMonthIsLeftOut() {
        let days = [day(trg, Fixture.date(2026, 9, 30)), day(kai, Fixture.date(2026, 10, 1))]

        let result = plan(sites: [trg, kai], days: days, today: Fixture.date(2026, 10, 21))

        XCTAssertEqual(result.map(\.siteID), [kai.id])
    }

    func testAnArchivedSiteIsLeftOut() {
        var archived = trg
        archived.isArchived = true

        let result = plan(sites: [archived], days: [day(trg, Fixture.date(2026, 10, 14))], today: Fixture.date(2026, 10, 21))

        XCTAssertEqual(result, [])
    }

    /// On the 1st itself, before the time, the reminder is still to come and
    /// is about the month that has just ended.
    func testOnTheFirstBeforeTheTimeItIsToday() {
        let result = plan(
            sites: [trg],
            days: [day(trg, Fixture.date(2026, 10, 30))],
            today: Fixture.date(2026, 11, 1),
            now: TimeOfDay(hour: 8, minute: 59)
        )

        XCTAssertEqual(result.map(\.date), [Fixture.date(2026, 11, 1)])
        XCTAssertEqual(result.map(\.month), [YearMonth(year: 2026, month: 10)])
    }

    /// Once the time has passed it has fired, and the next one is a month
    /// away — about this month, which has nothing on it yet.
    func testOnTheFirstAfterTheTimeItIsNextMonth() {
        let days = [day(trg, Fixture.date(2026, 10, 30)), day(trg, Fixture.date(2026, 11, 1))]

        let result = plan(sites: [trg], days: days, today: Fixture.date(2026, 11, 1), now: nine)

        XCTAssertEqual(result.map(\.date), [Fixture.date(2026, 12, 1)])
        XCTAssertEqual(result.map(\.month), [YearMonth(year: 2026, month: 11)])
    }

    func testDecemberIsSentInJanuary() {
        let result = plan(sites: [trg], days: [day(trg, Fixture.date(2026, 12, 18))], today: Fixture.date(2026, 12, 31))

        XCTAssertEqual(result.map(\.date), [Fixture.date(2027, 1, 1)])
        XCTAssertEqual(result.map(\.month), [YearMonth(year: 2026, month: 12)])
    }

    func testTheMonthItCovers() {
        XCTAssertEqual(
            MonthlySheetReminderPlan.coveredMonth(today: Fixture.date(2026, 10, 21), now: nine, time: nine),
            YearMonth(year: 2026, month: 10)
        )
        XCTAssertEqual(
            MonthlySheetReminderPlan.coveredMonth(today: Fixture.date(2026, 11, 1), now: TimeOfDay(hour: 7, minute: 0), time: nine),
            YearMonth(year: 2026, month: 10)
        )
    }

    func testSwitchedOnAtNineByDefault() {
        let prefs = ReminderPreferences()

        XCTAssertTrue(prefs.monthlySheetEnabled)
        XCTAssertEqual(prefs.monthlySheetTime, nine)
    }

    func testPreferencesWrittenBeforeItExistedDecodeWithItOn() throws {
        let json = #"{"isEnabled":true,"weekday":5,"time":{"hour":16,"minute":0},"siteRemindersEnabled":false}"#
        let prefs = try JSONDecoder().decode(ReminderPreferences.self, from: Data(json.utf8))

        XCTAssertTrue(prefs.monthlySheetEnabled)
        XCTAssertEqual(prefs.monthlySheetTime, nine)
        XCTAssertFalse(prefs.siteRemindersEnabled)
    }

    func testPreferencesRoundTrip() throws {
        let prefs = ReminderPreferences(monthlySheetEnabled: false, monthlySheetTime: TimeOfDay(hour: 7, minute: 30))
        let decoded = try JSONDecoder().decode(ReminderPreferences.self, from: JSONEncoder().encode(prefs))

        XCTAssertEqual(decoded, prefs)
    }

    func testMonthNameStandsAlone() {
        let formatting = CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)

        XCTAssertEqual(formatting.monthName(YearMonth(year: 2026, month: 10)), "October")
    }
}
