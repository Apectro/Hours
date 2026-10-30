import XCTest

/// The arrival reminder in a site's settings (1.2). There is no real
/// location permission in CI: under `-hours-ui-testing` the app's location
/// is a fake that hands out a fixed place in Zagreb and whatever access the
/// launch arguments ask for (`ArrivalLocation`). Found by identifier, never
/// by the translated words.
final class ArrivalReminderUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTurningTheReminderOnExplainsFirstThenSavesThePlace() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSiteSettings(app)
        openArrivalReminder(app)

        let toggle = app.switches["site-editor-arrival"].firstMatch
        scroll(to: toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0", "the reminder is off unless turned on")
        flip(toggle)

        // The explanation comes before anything is asked of iOS.
        let explanation = app.staticTexts["site-arrival-explanation"].firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5), "turning the reminder on should explain it first")
        let proceed = app.buttons["site-arrival-continue"].firstMatch
        XCTAssertTrue(proceed.exists, "the explanation should offer Continue")
        proceed.tap()

        // The fake's place is saved, shown as coordinates and a map.
        let coordinates = app.descendants(matching: .any)["site-arrival-coordinates"].firstMatch
        // The site's settings now hold the usual day and extras too, so the
        // place can land below the fold, where a Form has not made it yet.
        if !coordinates.waitForExistence(timeout: 5) { scroll(to: coordinates, in: app) }
        XCTAssertTrue(coordinates.waitForExistence(timeout: 5), "the site's place should show once saved")
        XCTAssertTrue(coordinates.label.contains("45.81302"), "the place should read as coordinates: \(coordinates.label)")
        XCTAssertTrue(app.descendants(matching: .any)["site-arrival-map"].firstMatch.exists, "a small map should show the place")
        XCTAssertEqual(app.switches["site-editor-arrival"].firstMatch.value as? String, "1", "the reminder should now be on")
        XCTAssertFalse(app.buttons["site-arrival-settings"].firstMatch.exists, "with Always given, nothing is missing")

        // Back to the site's settings, which save it.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(identifier: "site-editor-save").firstMatch.tap()

        // Saved with the site.
        openSiteSettings(app, fromSite: true)
        openArrivalReminder(app)
        let saved = app.descendants(matching: .any)["site-arrival-coordinates"].firstMatch
        scroll(to: saved, in: app)
        XCTAssertTrue(saved.exists, "the place should be kept with the site")

        // Clear location forgets it and turns the reminder off.
        let clear = app.buttons["site-arrival-clear"].firstMatch
        scroll(to: clear, in: app)
        clear.tap()
        XCTAssertFalse(saved.waitForExistence(timeout: 2), "Clear location should remove the place")
        XCTAssertEqual(app.switches["site-editor-arrival"].firstMatch.value as? String, "0")
    }

    func testWithoutAlwaysTheSectionSaysSoAndLeadsToSettings() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-location-no-always"]
        app.launch()
        openSiteSettings(app)
        openArrivalReminder(app)

        let toggle = app.switches["site-editor-arrival"].firstMatch
        scroll(to: toggle, in: app)
        flip(toggle)
        let proceed = app.buttons["site-arrival-continue"].firstMatch
        XCTAssertTrue(proceed.waitForExistence(timeout: 5), "turning the reminder on should explain it first")
        proceed.tap()

        let settings = app.buttons["site-arrival-settings"].firstMatch
        scroll(to: settings, in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "without Always the section should lead to Settings")
    }

    func testNotNowLeavesTheReminderOff() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSiteSettings(app)
        openArrivalReminder(app)

        let toggle = app.switches["site-editor-arrival"].firstMatch
        scroll(to: toggle, in: app)
        flip(toggle)
        let cancel = app.buttons["site-arrival-cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertEqual(app.switches["site-editor-arrival"].firstMatch.value as? String, "0")
        XCTAssertFalse(app.descendants(matching: .any)["site-arrival-coordinates"].firstMatch.exists, "nothing was saved")
    }

    // MARK: - Helpers

    /// The arrival reminder's own page (1.2), from the site's settings.
    private func openArrivalReminder(_ app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "site-editor-arrival-row").firstMatch
        scroll(to: row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the site's settings have no Arrival reminder row")
        row.tap()
        XCTAssertTrue(app.switches["site-editor-arrival"].firstMatch.waitForExistence(timeout: 5), "the arrival reminder did not open")
    }

    private func openSiteSettings(_ app: XCUIApplication, fromSite: Bool = false) {
        if !fromSite {
            XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
            app.tab(.sites).tap()
            let card = app.buttons["site-card"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
            card.tap()
        }
        // The gear in the site's toolbar: its settings.
        app.openSiteSettings()
        XCTAssertTrue(app.textFields["site-name"].waitForExistence(timeout: 5), "the site's settings did not open")
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
