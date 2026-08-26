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
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureTheListing() {
        let app = launchForShots()

        // 1 — the calendar, which is what the app is.
        capture("01-calendar", app)

        // 2 — a day open, showing what one holds.
        let today = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-'")).firstMatch
        if today.waitForExistence(timeout: 5) {
            today.tap()
            if app.buttons["day-editor-save"].waitForExistence(timeout: 3) {
                capture("02-day-editor", app)
                app.buttons["day-editor-cancel"].tap()
            } else {
                today.tap()
                if app.buttons["day-editor-save"].waitForExistence(timeout: 3) {
                    capture("02-day-editor", app)
                    app.buttons["day-editor-cancel"].tap()
                }
            }
        }

        // 3 — the month's figures.
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        capture("03-insights", app)

        // 4 — settings, which is where the configurability shows.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("04-settings", app)

        // 5 — the privacy screen, which is the reason to choose this one.
        let privacy = app.staticTexts["Privacy"]
        for _ in 0..<5 where !(privacy.exists && privacy.isHittable) {
            app.swipeUp()
        }
        if privacy.exists, privacy.isHittable {
            privacy.tap()
            if app.navigationBars["Privacy"].waitForExistence(timeout: 5) {
                capture("05-privacy", app)
            }
        }
    }
}
