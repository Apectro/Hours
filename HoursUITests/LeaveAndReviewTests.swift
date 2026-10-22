import XCTest

/// Settings › Leave and the year in review open, and come back.
///
/// Found by identifier and by position — the tab bar, the period picker's
/// segments — never by label, which is translated.
final class LeaveAndReviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 5) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    func testTheLeaveScreenOpensAndComesBack() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10))
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 5))

        let row = app.buttons["settings-leave"]
        XCTAssertTrue(reveal(row, in: app), "the Leave row is not there")
        row.tap()
        XCTAssertTrue(app.screen("screen-leave").waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["leave-allowance"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 5))
    }

    /// From a fresh install the year is empty, so this is also the empty
    /// state: friendly, and closable.
    func testTheYearInReviewOpensFromInsightsAndCloses() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tab(.insights).waitForExistence(timeout: 10))
        app.tab(.insights).tap()
        XCTAssertTrue(app.screen("screen-insights").waitForExistence(timeout: 5))

        // Today, Week, Month, Year: the fourth segment.
        let year = app.segmentedControls.firstMatch.buttons.element(boundBy: 3)
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        year.tap()

        let open = app.buttons["insights-year-review"]
        XCTAssertTrue(reveal(open, in: app), "the review button is not on the year")
        open.tap()

        XCTAssertTrue(app.screen("year-review-empty").waitForExistence(timeout: 5))
        app.buttons["year-review-close"].tap()
        XCTAssertTrue(app.screen("screen-insights").waitForExistence(timeout: 5))
    }
}
