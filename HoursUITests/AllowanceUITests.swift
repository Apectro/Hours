import XCTest

/// Field allowance and travel (1.2): switched on in Settings, set on a day
/// and seen in the month's summary; and on a site, given to one person from
/// their row's menu. Found by identifier, never by the translated words.
final class AllowanceUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAnAllowanceOnADayShowsInTheMonthSummary() {
        let app = XCUIApplication.hours()
        app.launch()
        switchOnAllowance(app)

        // Today, with the field allowance and some kilometres.
        app.tab(.calendar).tap()
        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the day editor did not open")
        // On the editor's extras page (1.2): "Allowance, km, note…".
        let extras = app.buttons["day-editor-more"].firstMatch
        scroll(to: extras, in: app)
        extras.tap()
        let allowance = app.switches["day-editor-allowance"].firstMatch
        scroll(to: allowance, in: app)
        flip(allowance)
        XCTAssertEqual(allowance.value as? String, "1", "the day's allowance should be on")
        let kilometres = app.textFields["day-editor-kilometres"].firstMatch
        scroll(to: kilometres, in: app)
        kilometres.tap()
        kilometres.typeText("84")
        app.buttons["day-extras-done"].firstMatch.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5), "Done did not return to the editor")
        save.tap()
        XCTAssertFalse(save.waitForExistence(timeout: 2), "the editor stayed open after saving")
        // Back from the day to Today, where the month and its totals are.
        if app.screen("screen-calendar-day").exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        // The month's summary under the calendar has its line.
        let line = app.descendants(matching: .any)["calendar-summary-allowance"].firstMatch
        scroll(to: line, in: app)
        XCTAssertTrue(line.exists, "the month summary should show the allowance")
        XCTAssertTrue(line.label.contains("84"), "the line should carry the kilometres: \(line.label)")

        // And Insights' month has it too.
        app.tab(.insights).tap()
        let insights = app.descendants(matching: .any)["insights-allowance"].firstMatch
        scroll(to: insights, in: app)
        XCTAssertTrue(insights.exists, "Insights should show the allowance")
    }

    func testASiteDayGivesOnePersonTheAllowanceFromTheirRow() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        switchOnAllowance(app)

        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        // Today from yesterday: everyone ticked in, nobody with the
        // allowance, since the site gives none by default.
        let same = app.buttons["site-day-same-as-last"]
        XCTAssertTrue(same.waitForExistence(timeout: 5), "an empty day should offer Same as last day")
        same.tap()
        let ivan = app.buttons["site-person-Ivan"]
        XCTAssertTrue(ivan.waitForExistence(timeout: 5))
        XCTAssertFalse(hasAllowance(ivan), "nobody has the allowance until it is given")

        // The row's menu gives it, and takes it back.
        ivan.press(forDuration: 1.0)
        let item = app.buttons["site-person-allowance"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the row's menu should offer the allowance")
        item.tap()
        expect(ivan, hasAllowance: true)

        ivan.press(forDuration: 1.0)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        expect(ivan, hasAllowance: false)

        // The vehicle's kilometres for the day.
        let kilometres = app.textFields["site-day-kilometres"].firstMatch
        scroll(to: kilometres, in: app)
        XCTAssertTrue(kilometres.exists, "the site day should offer kilometres")
    }

    // MARK: - Helpers

    private func switchOnAllowance(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10))
        app.tab(.settings).tap()
        // Under Pay, which includes the allowance and travel. Found by
        // identifier whatever its type: the row is sometimes reported as a
        // pop-up button rather than a button, and then a query for buttons
        // finds nothing and swipes past it.
        let pay = app.descendants(matching: .any)["settings-pay"].firstMatch
        scroll(to: pay, in: app)
        pay.tap()
        let row = app.descendants(matching: .any)["settings-allowance"].firstMatch
        scroll(to: row, in: app)
        row.tap()
        let enabled = app.switches["allowance-enabled"].firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 5), "the allowance settings did not open")
        flip(enabled)
        let perDay = app.textFields["allowance-per-day"].firstMatch
        XCTAssertTrue(perDay.waitForExistence(timeout: 5), "switched on, the rates should show")
        perDay.tap()
        perDay.typeText("30")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// The row's value names the allowance (VoiceOver's "field allowance").
    private func hasAllowance(_ row: XCUIElement) -> Bool {
        (row.value as? String)?.contains("field allowance") == true
    }

    private func expect(_ row: XCUIElement, hasAllowance expected: Bool) {
        let predicate = NSPredicate { _, _ in self.hasAllowance(row) == expected }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: row)], timeout: 5)
        XCTAssertEqual(result, .completed, "Ivan should \(expected ? "have" : "not have") the allowance: \(String(describing: row.value))")
    }

    /// A Form switch: its own knob when it can be hit, else the trailing
    /// edge of the row where the knob is drawn.
    private func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(toggle) is missing")
        let inner = toggle.switches.firstMatch
        if inner.exists, inner.isHittable {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    private func scroll(to element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
    }
}
