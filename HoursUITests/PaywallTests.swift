import XCTest

/// What someone who has not paid sees.
///
/// The unit tests cover what the entitlement means; these cover what the app
/// does about it. They matter because the gates are five separate call sites
/// that could each be wrong in their own way, and because a paywall that
/// appears where it should not is a bug nobody reports — they just leave.
final class PaywallTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Settings is longer than a screen — more so since the Pro row went on
    /// top of it — so anything in the last section has to be scrolled to
    /// before it can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 5) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func openSettings(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testAnUnpaidAppOffersTheUpgrade() {
        let app = XCUIApplication.hours()
        openSettings(app)

        XCTAssertTrue(app.staticTexts["Unlock Zeitkonto Pro"].exists)
    }

    func testAPaidAppStopsAsking() {
        let app = XCUIApplication.hours(pro: true)
        openSettings(app)

        XCTAssertTrue(app.staticTexts["Zeitkonto Pro"].exists)
        XCTAssertFalse(
            app.staticTexts["Unlock Zeitkonto Pro"].exists,
            "someone who has paid should never be asked again"
        )
    }

    /// The part of the paywall that is a promise rather than a pitch. If this
    /// list ever stops naming the backup file, someone has quietly made a
    /// person's own work record conditional on paying.
    ///
    /// Every line of `ProFeature.alwaysFree`, word for word as the sheet
    /// draws it (checked against the paywall on 2026-10-23); a line changed
    /// there is a promise changed, and should be changed here on purpose.
    func testThePaywallSaysWhatStaysFree() {
        let app = XCUIApplication.hours()
        openSettings(app)
        app.staticTexts["Unlock Zeitkonto Pro"].tap()

        XCTAssertTrue(app.staticTexts["Free, whatever you decide"].waitForExistence(timeout: 5))
        for line in [
            "Recording and editing your hours",
            "The calendar, the balance and every total",
            "Reminders about days you have not filled in",
            "The backup file, which holds everything you ever recorded"
        ] {
            XCTAssertTrue(app.staticTexts[line].exists, "the paywall no longer promises \"\(line)\" for free")
        }
    }

    /// Reachable and dismissable. A paywall that traps someone is worse than
    /// no paywall.
    func testThePaywallCanBeDeclined() {
        let app = XCUIApplication.hours()
        openSettings(app)
        app.staticTexts["Unlock Zeitkonto Pro"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))

        app.buttons["Not now"].tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// Backup is the free way to get every recorded hour off the device, and
    /// it must open without being asked for money.
    func testTheBackupScreenIsNotBehindThePaywall() {
        let app = XCUIApplication.hours()
        openSettings(app)

        // Backup lives under "iCloud & backup" since Settings was regrouped.
        let hub = app.staticTexts["iCloud & backup"]
        XCTAssertTrue(reveal(hub, in: app), "iCloud & backup should be reachable without paying")
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "the list settles")], timeout: 1)
        hub.tap()
        let row = app.staticTexts["Backup and data"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the backup row should be reachable without paying")
        // reveal() stops swiping as soon as the row is on screen, while the
        // list is still gliding; a tap in that moment can land on nothing,
        // and Settings now holds enough rows (iCloud among them) for the
        // row to arrive mid-glide. Let the list come to rest first.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "the list settles")], timeout: 1)
        row.tap()

        XCTAssertTrue(app.navigationBars["Backup and data"].waitForExistence(timeout: 10), "the backup screen did not open")
        XCTAssertFalse(app.buttons["Not now"].exists, "no paywall stands in front of your own data")
    }
}
