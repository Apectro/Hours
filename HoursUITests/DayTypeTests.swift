import XCTest

/// Settings › Day types: a paid-absence type's "Paid at", and Sick's
/// "Employer pays the first 42 days".
///
/// Read by identifier and by the percentage, which is digits in every
/// language, never by the translated words.
final class DayTypeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSickCanBePaidAtAPercentageAndIsKept() {
        let app = XCUIApplication.hours()
        app.launch()
        openSick(app)

        // A fresh install pays sick leave in full, with no 42-day limit.
        let down = app.buttons.matching(identifier: "day-type-paid-at-down").firstMatch
        XCTAssertTrue(down.waitForExistence(timeout: 5), "a paid absence should offer Paid at")
        XCTAssertEqual(down.value as? String, "100%")
        XCTAssertFalse(app.buttons.matching(identifier: "day-type-paid-at-up").firstMatch.isEnabled, "100% is the most")

        // Down to 70%, six steps of five.
        for _ in 0..<6 { down.tap() }
        XCTAssertEqual(down.value as? String, "70%")

        let limit = app.switches["day-type-employer-42-days"]
        for _ in 0..<4 where !(limit.exists && limit.isHittable) { app.swipeUp() }
        XCTAssertTrue(limit.isHittable, "Sick should offer the 42-day rule")
        XCTAssertEqual(limit.value as? String, "0")
        // The switch itself, at the trailing edge, not the label.
        let knob = limit.switches.firstMatch
        if knob.exists, knob.isHittable {
            knob.tap()
        } else {
            limit.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(limit.value as? String, "1")

        app.buttons.matching(identifier: "day-type-editor-save").firstMatch.tap()

        // Opened again, it is as saved.
        openSickRow(app)
        let again = app.buttons.matching(identifier: "day-type-paid-at-down").firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.value as? String, "70%", "Paid at should be kept")
        let kept = app.switches["day-type-employer-42-days"]
        for _ in 0..<4 where !(kept.exists && kept.isHittable) { app.swipeUp() }
        XCTAssertEqual(kept.value as? String, "1", "the 42-day rule should be kept")
        app.buttons.matching(identifier: "day-type-editor-cancel").firstMatch.tap()
    }

    /// A type that is not paid absence has no pay to set.
    func testAWorkingDayTypeHasNoPaidAt() {
        let app = XCUIApplication.hours()
        app.launch()
        openDayTypes(app)
        // Work is first.
        app.buttons.matching(identifier: "day-types-row").element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "day-type-editor-cancel").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(identifier: "day-type-paid-at-down").firstMatch.exists)
        app.buttons.matching(identifier: "day-type-editor-cancel").firstMatch.tap()
    }

    // MARK: - Getting there

    private func openDayTypes(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10))
        app.tab(.settings).tap()
        // Under Day types & holidays.
        let hub = app.buttons.matching(identifier: "settings-day-types-holidays").firstMatch
        for _ in 0..<6 where !(hub.exists && hub.isHittable) { app.swipeUp() }
        XCTAssertTrue(hub.isHittable, "Settings has no Day types & holidays row")
        hub.tap()
        let row = app.buttons.matching(identifier: "settings-day-types").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Day types & holidays has no Day types row")
        row.tap()
        XCTAssertTrue(
            app.buttons.matching(identifier: "day-types-row").firstMatch.waitForExistence(timeout: 5),
            "Day types did not open"
        )
    }

    private func openSick(_ app: XCUIApplication) {
        openDayTypes(app)
        openSickRow(app)
    }

    /// Work, Weekend, Public holiday, Vacation, Sick: the fifth row.
    private func openSickRow(_ app: XCUIApplication) {
        let sick = app.buttons.matching(identifier: "day-types-row").element(boundBy: 4)
        XCTAssertTrue(sick.waitForExistence(timeout: 5), "no fifth day type")
        sick.tap()
        XCTAssertTrue(
            app.buttons.matching(identifier: "day-type-editor-save").firstMatch.waitForExistence(timeout: 5),
            "the editor did not open"
        )
    }
}
