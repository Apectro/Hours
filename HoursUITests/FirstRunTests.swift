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

    /// Continue on the name step. The keyboard is still sliding up when
    /// the field takes focus; a tap on Continue in that moment can land on
    /// nothing, so wait until it can actually be hit. On a smaller simulator
    /// the keyboard covers it outright, and then Return, which continues
    /// just the same, is what a person would press.
    private func continuePastTheName(_ app: XCUIApplication) {
        let next = app.buttons["setup-continue"]
        if hittable(next, timeout: 5) {
            next.tap()
        } else {
            app.textFields["setup-name"].typeText("\n")
        }
    }

    /// Each step waited for before its taps: taps in a row can land while a
    /// step is still sliding in, and a lost tap leaves the test a screen
    /// short of where it thinks it is.
    private func continuePast(_ step: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        XCTAssertTrue(app.screen(step).waitForExistence(timeout: timeout), "\(step) did not come")
        app.buttons["setup-continue"].tap()
    }

    func testContinuingThroughEveryStepEndsInTodaysEditor() {
        let app = launchWithSetup()

        let name = app.textFields["setup-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the setup was not shown")
        name.tap()
        name.typeText("Marijo")
        continuePastTheName(app)

        XCTAssertTrue(app.screen("screen-setup-week").waitForExistence(timeout: 10), "the week was not asked")
        // Saturday on, as someone who works six days would.
        app.buttons["setup-weekday-7"].tap()
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.screen("screen-setup-breaks").waitForExistence(timeout: 5), "the breaks were not asked")
        app.buttons["setup-breaks-paid"].tap()
        app.buttons["setup-continue"].tap()

        // No country chosen: nothing is added, and nothing is guessed.
        continuePast("screen-setup-holidays", in: app)

        // The report language: one of the ten, picked by hand.
        XCTAssertTrue(app.screen("screen-setup-language").waitForExistence(timeout: 5), "the report language was not asked")
        let german = app.buttons["setup-language-german"]
        for _ in 0..<3 where !german.isHittable { app.swipeUp() }
        german.tap()
        app.buttons["setup-continue"].tap()

        XCTAssertTrue(app.screen("screen-setup-crew").waitForExistence(timeout: 5), "the crew was not asked")
        app.buttons["setup-crew-no"].tap()
        app.buttons["setup-continue"].tap()

        // Pay is optional: continuing with no rate sets nothing up.
        continuePast("screen-setup-pay", in: app)

        XCTAssertTrue(app.screen("screen-setup-finish").waitForExistence(timeout: 5), "the last screen did not come")
        XCTAssertFalse(app.buttons["setup-create-site"].exists, "Create a site is for someone who leads a crew")
        app.buttons["setup-write-today"].tap()

        XCTAssertTrue(app.buttons["day-editor-save"].waitForExistence(timeout: 5), "today's editor did not open")
        app.buttons["day-editor-cancel"].tap()
        XCTAssertTrue(app.tab(.calendar).isSelected)
    }

    func testACrewLeadCanOpenANewSiteFromTheLastScreen() {
        let app = launchWithSetup()

        XCTAssertTrue(app.screen("screen-setup-name").waitForExistence(timeout: 10), "the setup was not shown")
        continuePastTheName(app)
        for step in ["screen-setup-week", "screen-setup-breaks", "screen-setup-holidays", "screen-setup-language"] {
            continuePast(step, in: app, timeout: 10)
        }
        XCTAssertTrue(app.screen("screen-setup-crew").waitForExistence(timeout: 5), "the crew was not asked")
        app.buttons["setup-crew-yes"].tap()
        app.buttons["setup-continue"].tap()
        continuePast("screen-setup-pay", in: app)

        XCTAssertTrue(app.screen("screen-setup-finish").waitForExistence(timeout: 5), "the last screen did not come")
        app.buttons["setup-create-site"].tap()

        // The new-site wizard, on its first step.
        XCTAssertTrue(app.buttons["wizard-start-fresh"].waitForExistence(timeout: 5), "the new-site wizard did not open")
    }

    /// "Show me around" ends the setup in the tour.
    func testTheLastScreenStartsTheTour() {
        let app = launchWithSetup()

        XCTAssertTrue(app.screen("screen-setup-name").waitForExistence(timeout: 10), "the setup was not shown")
        continuePastTheName(app)
        for step in ["screen-setup-week", "screen-setup-breaks", "screen-setup-holidays", "screen-setup-language",
                     "screen-setup-crew", "screen-setup-pay"] {
            continuePast(step, in: app, timeout: 10)
        }
        XCTAssertTrue(app.screen("screen-setup-finish").waitForExistence(timeout: 5), "the last screen did not come")
        app.buttons["setup-show-tour"].tap()

        XCTAssertTrue(app.buttons["tour-next"].waitForExistence(timeout: 10), "the tour did not start")
    }

    /// Skip ends the setup without the tour, on any step.
    func testSkipLaterStillSkipsTheTour() {
        let app = launchWithSetup()

        XCTAssertTrue(app.screen("screen-setup-name").waitForExistence(timeout: 10), "the setup was not shown")
        continuePastTheName(app)
        for step in ["screen-setup-week", "screen-setup-breaks", "screen-setup-holidays"] {
            continuePast(step, in: app, timeout: 10)
        }
        XCTAssertTrue(app.screen("screen-setup-language").waitForExistence(timeout: 5))
        app.buttons["setup-skip"].tap()

        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tour-next"].waitForExistence(timeout: 2), "Skip must not start the tour")
    }
}
