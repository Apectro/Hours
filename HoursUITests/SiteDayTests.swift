import XCTest

/// The site screen: its month, ticking the crew, a changed time standing
/// out, and a closed month refusing edits.
///
/// Every test starts from the seeded site (`SampleData.seedSite`):
/// "Kaiserstrasse 12" with Ivan and Marko on the crew, and yesterday written
/// up from 07:00 to 15:30 with a 30-minute break, Ivan leaving at 12:00.
/// Today is left empty. Run unpaid: the first site is free.
final class SiteDayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTickCrewAndSave() {
        let app = launch()
        openSite(app)

        // Today opens as not written, with yesterday on offer.
        XCTAssertTrue(app.screen("site-day-not-written").waitForExistence(timeout: 5), "today should say it is not written")
        let same = app.buttons["site-day-same-as-last"]
        XCTAssertTrue(same.waitForExistence(timeout: 5), "an empty day should offer Same as last day")
        // It names the day it copies from, which is yesterday, not today.
        XCTAssertTrue(
            same.label.contains(Self.mediumDate(daysFromToday: -1)),
            "Same as last day should name yesterday, \(Self.mediumDate(daysFromToday: -1)): \(same.label)"
        )
        same.tap()

        // Everyone who was there yesterday, at the site's times: Ivan's early
        // finish was a fact about yesterday and does not come with him.
        let you = app.buttons["site-person-you"]
        let ivan = app.buttons["site-person-Ivan"]
        let marko = app.buttons["site-person-Marko"]
        wait(for: you, selected: true)
        wait(for: ivan, selected: true)
        wait(for: marko, selected: true)
        XCTAssertFalse(app.buttons["site-times-Ivan"].label.contains("Left early"), "exceptions must not be copied")

        // Marko was somewhere else today.
        marko.tap()
        wait(for: marko, selected: false)
        XCTAssertTrue(app.buttons["site-times-Marko"].label.contains("Not here"))

        // Two people, eight hours each.
        let total = app.descendants(matching: .any)["site-crew-total"]
        if !total.exists { app.swipeUp() }
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("16"), "the crew total should be 16 hours: \(total.label)")

        // Saved with no Save button: leave the site and come back.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "could not get back to the list")
        app.buttons["site-card"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site did not open again")
        wait(for: app.buttons["site-person-you"], selected: true)
        wait(for: app.buttons["site-person-Ivan"], selected: true)
        wait(for: app.buttons["site-person-Marko"], selected: false)
    }

    func testLeftEarlyIsHighlighted() {
        let app = launch()
        openSite(app)

        select(app, daysFromToday: -1)

        let ivanTimes = app.buttons["site-times-Ivan"]
        XCTAssertTrue(ivanTimes.waitForExistence(timeout: 5))
        let leftEarly = NSPredicate(format: "label CONTAINS %@", "Left early")
        expectation(for: leftEarly, evaluatedWith: ivanTimes)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(ivanTimes.label.contains("12:00"), "Ivan's own end time should show: \(ivanTimes.label)")

        // Only Ivan: Marko and you kept the site's times.
        XCTAssertFalse(app.buttons["site-times-Marko"].label.contains("Left early"))
        XCTAssertFalse(app.buttons["site-times-you"].label.contains("Left early"))
    }

    func testLockedMonthShowsRefusal() {
        let app = launch(arguments: ["-hours-closed-month"])
        openSite(app)

        // The day says why it cannot be changed, in the calendar's words.
        XCTAssertTrue(app.screen("site-day-locked").waitForExistence(timeout: 5), "a closed month must say so")
        XCTAssertTrue(app.staticTexts["This month is closed"].exists || app.screen("site-day-locked").label.contains("This month is closed"))

        // And nothing can be ticked or copied into it.
        let ivan = app.buttons["site-person-Ivan"]
        XCTAssertTrue(ivan.waitForExistence(timeout: 5))
        XCTAssertFalse(ivan.isEnabled, "ticking must be off in a closed month")
        ivan.tap()
        XCTAssertFalse(ivan.isSelected, "a tick in a closed month must not take")
        let same = app.buttons["site-day-same-as-last"]
        if same.exists {
            XCTAssertFalse(same.isEnabled, "Same as last day must be off in a closed month")
        }
    }

    /// Tapping a day in the site's month shows that day on the card, and
    /// tapping back shows today again — with nobody ticked once it is
    /// started from empty.
    func testTappingADayInTheMonthShowsIt() {
        let app = launch()
        openSite(app)

        let yesterday = select(app, daysFromToday: -1)
        wait(for: yesterday, selected: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5),
            "yesterday is written, so its card should show the crew's total"
        )
        wait(for: app.buttons["site-person-Ivan"], selected: true)
        XCTAssertFalse(app.screen("site-day-not-written").exists, "a written day must not say it is not written")

        let today = select(app, daysFromToday: 0)
        wait(for: today, selected: true)
        wait(for: yesterday, selected: false)
        XCTAssertTrue(app.screen("site-day-not-written").waitForExistence(timeout: 5), "today is not written")

        let empty = app.buttons["site-day-start-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an empty day should offer Start from empty")
        empty.tap()
        wait(for: app.buttons["site-person-you"], selected: false)
        wait(for: app.buttons["site-person-Ivan"], selected: false)
    }

    // MARK: - Helpers

    /// Taps a day's cell in the site's month and returns it. A day outside
    /// the month on screen — yesterday on the 1st, say — may not be in the
    /// grid at all, so the arrows move to its month first.
    @discardableResult
    private func select(_ app: XCUIApplication, daysFromToday offset: Int) -> XCUIElement {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        let cell = app.buttons["site-day-\(key)"]
        if !cell.waitForExistence(timeout: 3) {
            // The tests only ever step back from today's month and return to
            // it, so the direction follows from the offset.
            app.buttons[offset < 0 ? "site-month-previous" : "site-month-next"].tap()
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "the site's month has no cell for \(key)")
        cell.tap()
        return cell
    }

    /// A date as the app's day headings write it ("Tue 19 Oct" in English),
    /// in the simulator's own locale, which is the one the app runs in.
    private static func mediumDate(daysFromToday offset: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"] + arguments
        app.launch()
        return app
    }

    private func openSite(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")
    }

    /// Ticks are read from the selected trait rather than a label, which is
    /// translated.
    private func wait(for element: XCUIElement, selected: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is missing", file: file, line: line)
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.identifier) should be \(selected ? "ticked" : "unticked")", file: file, line: line)
    }
}
