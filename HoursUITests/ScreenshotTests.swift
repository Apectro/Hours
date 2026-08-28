import XCTest

/// Takes the pictures that go on the App Store listing.
///
/// Not a test of anything, and honest about that — every assertion here is a
/// precondition for the shot being worth keeping, not a claim about the app.
/// It lives in the test target because that is the only thing that can drive a
/// simulator, and because the alternative is hand-entering a month on a device
/// to photograph it, which is the work this app exists to avoid.
///
/// CI exports the attachments; see the "App Store screenshots" step.
///
/// Nothing here is found by its label, because this suite is run twice: once
/// in English and once in German, to produce a set of screenshots per
/// language. A test that waits for `buttons["Calendar"]` passes in one
/// language and hangs in the other.
///
/// The tabs are reached by position rather than by identifier. An
/// `accessibilityIdentifier` on a tab applies to that tab's content view, not
/// to its button in the tab bar, so the identifier is simply never there to
/// find — which is what the first attempt at this discovered, in CI, after a
/// fifteen-second wait and a red run.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Sample data and Pro, because a listing should show the app doing its
    /// job rather than an empty calendar and a row of locks.
    private func launchForShots() -> XCUIApplication {
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-data"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        taken.append(name)
    }

    /// Settings is taller than a screen, so a row near the bottom has to be
    /// brought up before it can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Which shots actually got taken. The first version of this test wrapped
    /// every capture in `if it exists`, so a screen that failed to open simply
    /// produced no picture and a green tick — four files where five were
    /// expected, and nothing in the log saying which one was missing.
    private var taken: [String] = []

    func testCaptureTheListing() {
        let app = launchForShots()

        // 1 — the calendar, which is what the app is.
        capture("01-calendar", app)

        // 2 — a day open, showing what one holds. Today, because the sample
        // month is seeded around it and because it is the day already selected.
        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the day editor did not open")
        capture("02-day-editor", app)
        app.buttons["day-editor-cancel"].tap()

        // 3 — the month's figures.
        app.tab(.insights).tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 10))
        capture("03-insights", app)

        // 4 — settings, which is where the configurability shows.
        app.tab(.settings).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        capture("04-settings", app)

        // 5 — the privacy screen, which is the reason to choose this one.
        let privacy = app.buttons["settings-privacy"]
        XCTAssertTrue(reveal(privacy, in: app), "could not scroll Settings down to Privacy")
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 10))
        capture("05-privacy", app)

        // 6 — the export screen, reached from the calendar's overflow menu.
        app.tab(.calendar).tap()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.buttons["calendar-more"].tap()
        let exportItem = app.buttons["calendar-export"]
        XCTAssertTrue(exportItem.waitForExistence(timeout: 5), "the overflow menu has no Export item")
        exportItem.tap()
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10), "Export did not open")
        capture("10-export", app)

        XCTAssertEqual(
            taken,
            [
                "01-calendar", "02-day-editor", "03-insights",
                "04-settings", "05-privacy", "10-export",
            ],
            "a screenshot is missing"
        )
    }
}
