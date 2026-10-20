import XCTest

/// The site day screen: ticking the crew, a changed time standing out, and a
/// closed month refusing edits.
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

        // Today opens empty, with yesterday on offer.
        let you = app.buttons["site-person-you"]
        XCTAssertTrue(you.waitForExistence(timeout: 5), "the crew list is missing")
        XCTAssertFalse(you.isSelected, "a new day must start with nobody ticked")
        let same = app.buttons["site-day-same-as-last"]
        XCTAssertTrue(same.exists, "an empty day should offer Same as last day")
        same.tap()

        // Everyone who was there yesterday, at the site's times: Ivan's early
        // finish was a fact about yesterday and does not come with him.
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

        app.buttons["site-day-previous"].tap()

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

    // MARK: - Helpers

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
