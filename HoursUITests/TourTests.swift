import XCTest

/// The guided tour: six stops over the real screens.
///
/// Never shown to a UI test that does not ask: `-hours-tour` starts it at
/// launch, the way `-hours-first-run` shows the setup.
final class TourTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchWithTour() -> XCUIApplication {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-tour"]
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

    func testTheOtherTestsNeverSeeIt() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tour-next"].waitForExistence(timeout: 2), "the tour was shown to a test that did not ask")
    }

    func testNextThroughEveryStopThenDoneEndsOnTheCalendar() {
        let app = launchWithTour()

        // Five times Next: each waited for, since a stop can take a moment
        // to find what it points at after switching tabs.
        for stop in 1...5 {
            let next = app.buttons["tour-next"]
            XCTAssertTrue(hittable(next), "Next was not offered on stop \(stop)")
            next.tap()
        }

        let done = app.buttons["tour-done"]
        XCTAssertTrue(hittable(done), "the last stop did not offer Done")
        XCTAssertFalse(app.buttons["tour-next"].exists, "the last stop has no Next")
        done.tap()

        XCTAssertFalse(app.staticTexts["tour-card"].waitForExistence(timeout: 2), "the tour stayed up after Done")
        XCTAssertTrue(app.tab(.calendar).isSelected, "Done did not end on the calendar")
    }

    func testSkipEndsTheTour() {
        let app = launchWithTour()

        let skip = app.buttons["tour-skip"]
        XCTAssertTrue(hittable(skip), "the tour did not start")
        skip.tap()

        XCTAssertFalse(app.buttons["tour-next"].waitForExistence(timeout: 2), "the tour stayed up after Skip")
        XCTAssertTrue(app.tab(.calendar).isSelected)
    }

    func testSettingsShowsTheTourAgain() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10))
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 5))

        // Under More › Help & tour.
        XCTAssertTrue(app.openSettingsMore(), "Settings has no More row")
        let help = app.buttons["settings-help"]
        for _ in 0..<6 where !(help.exists && help.isHittable) { app.swipeUp() }
        XCTAssertTrue(hittable(help, timeout: 5), "Settings has no Help & tour")
        help.tap()
        let again = app.buttons["settings-show-tour"]
        XCTAssertTrue(hittable(again, timeout: 5), "Show the tour again was not in Help & tour")
        again.tap()

        // The card is modal to accessibility, so the tab bar is not
        // asserted while it is up.
        XCTAssertTrue(hittable(app.buttons["tour-next"]), "the tour did not start from Settings")
    }
}
