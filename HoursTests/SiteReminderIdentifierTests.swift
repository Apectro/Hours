import XCTest
@testable import Hours

/// The name a site reminder is scheduled and cancelled under.
final class SiteReminderIdentifierTests: XCTestCase {
    func testIdentifierIsThePrefixAndTheDateKey() {
        let id = ReminderScheduler.siteReminderIdentifier(for: CalendarDate(year: 2026, month: 8, day: 4))
        XCTAssertEqual(id, "site-reminder-20260804")
    }

    func testDifferentDatesGetDifferentIdentifiers() {
        let a = ReminderScheduler.siteReminderIdentifier(for: CalendarDate(year: 2026, month: 8, day: 4))
        let b = ReminderScheduler.siteReminderIdentifier(for: CalendarDate(year: 2026, month: 8, day: 5))
        XCTAssertNotEqual(a, b)
    }

    func testTheWeeklyReminderIsNotASiteReminder() {
        XCTAssertFalse(ReminderScheduler.identifier.hasPrefix(ReminderScheduler.siteIdentifierPrefix))
    }
}
