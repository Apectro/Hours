import XCTest

/// The questions a fresh install asks once.
///
/// Every other UI test starts from an empty store and default settings, which
/// is what a fresh install looks like, so the app shows the setup to them only
/// when `-hours-first-run` asks it to. These are the tests that ask.
final class FirstRunTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchWithSetup() -> XCUIApplication {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-first-run"]
        app.launch()
        return app
    }

    private func hittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Without the argument it is never shown: what the rest of the suite
    /// relies on.
    func testTheOtherTestsNeverSeeIt() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        XCTAssertFalse(app.screen("screen-setup-name").exists, "the setup was shown to a UI test that did not ask for it")
    }

    func testSkipGoesStraightToTheCalendar() {
        let app = launchWithSetup()

        XCTAssertTrue(app.screen("screen-setup-name").waitForExistence(timeout: 10), "the setup was not shown")
        app.buttons["setup-skip"].tap()

        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 5))
        XCTAssertTrue(app.tab(.calendar).isSelected)
        XCTAssertFalse(app.screen("screen-setup-name").exists, "the setup stayed up after Skip")
    }

    func testContinuingThroughEveryStepEndsInTodaysEditor() {
        let app = launchWithSetup()

        let name = app.textFields["setup-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the setup was not shown")
        name.tap()
        name.typeText("Marijo")
        // The keyboard is still sliding up when typing ends; a tap on
        // Continue in that moment can land on nothing. Wait until it can
        // actually be hit.
        let next = app.buttons["setup-continue"]
        XCTAssertTrue(hittable(next), "Continue could not be tapped with the keyboard up")
        next.tap()

        XCTAssertTrue(app.screen("screen-setup-week").waitForExistence(timeout: 10), "the week was not asked")
        // Saturday on, as someone who works six days would.
        app.buttons["setup-weekday-7"].tap()
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.screen("screen-setup-breaks").waitForExistence(timeout: 5), "the breaks were not asked")
        app.buttons["setup-breaks-paid"].tap()
        app.buttons["setup-continue"].tap()

        // No country chosen: nothing is added, and nothing is guessed.
        XCTAssertTrue(app.screen("screen-setup-holidays").waitForExistence(timeout: 5), "the country was not asked")
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.screen("screen-setup-finish").waitForExistence(timeout: 5), "the last screen did not come")
        app.buttons["setup-write-today"].tap()

        XCTAssertTrue(app.buttons["day-editor-save"].waitForExistence(timeout: 5), "today's editor did not open")
        app.buttons["day-editor-cancel"].tap()
        XCTAssertTrue(app.tab(.calendar).isSelected)
    }

    func testTheLastScreenCanOpenANewSite() {
        let app = launchWithSetup()

        // Each step waited for before the next tap: four taps in a row can
        // land while a step is still sliding in, and a lost tap leaves the
        // test a screen short of where it thinks it is.
        for step in ["screen-setup-name", "screen-setup-week", "screen-setup-breaks", "screen-setup-holidays"] {
            XCTAssertTrue(app.screen(step).waitForExistence(timeout: 10), "\(step) did not come")
            app.buttons["setup-continue"].tap()
        }
        XCTAssertTrue(app.screen("screen-setup-finish").waitForExistence(timeout: 5), "the last screen did not come")
        app.buttons["setup-create-site"].tap()

        XCTAssertTrue(app.textFields["site-name"].waitForExistence(timeout: 5), "the site editor did not open")
    }
}
