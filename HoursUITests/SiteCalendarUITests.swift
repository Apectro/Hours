import XCTest

/// A site's month draws public holidays as the calendar does (2026-11-05,
/// "on sites calendar holidays aren't shown"): the seeded site
/// (`-hours-sample-site`) with a holiday of your own, "Site Holiday", on the
/// 1st of this month (`-hours-site-holiday`). The day says the holiday's
/// name, which is the user's own text and not translated, and opens as any
/// other day.
final class SiteCalendarUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `yyyyMMdd` for the 1st of this month: the seeded holiday.
    private var firstOfMonthKey: Int {
        let parts = Calendar.current.dateComponents([.year, .month], from: Date())
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + 1
    }

    func testAHolidayOnTheSitesMonthSaysItsNameAndOpensTheDay() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-site-holiday"]
        app.launch()
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()

        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5), "the site did not open")

        let holiday = app.buttons.matching(identifier: "site-overview-day-\(firstOfMonthKey)").firstMatch
        XCTAssertTrue(holiday.waitForExistence(timeout: 5), "the 1st is not in the site's month")
        let named = NSPredicate(format: "label CONTAINS %@", "Site Holiday")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: named, object: holiday)], timeout: 5),
            .completed,
            "the holiday does not say its name: \(holiday.label)"
        )

        // A tap opens the day, as on any other day.
        let bar = app.buttons.matching(identifier: "site-write-today").firstMatch
        XCTAssertTrue(app.tapAboveBottomBar(holiday, bar: bar), "the holiday could not be tapped")
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the holiday did not open its day")
    }
}
