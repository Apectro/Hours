import XCTest

/// The app starts, and the screens it starts on are there.
///
/// Two hundred unit tests cover the arithmetic and none of them would notice
/// the app crashing on launch, a container that refuses to open, or a tab that
/// never appears. These are the tests that would.
final class LaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheAppLaunchesOnTheCalendar() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Insights"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected, "the calendar is the landing screen")
    }

    /// The store failing to open shows a banner. It must not be there on a
    /// healthy launch, or nobody will believe it when it is.
    func testNoStoreFailureBannerOnAHealthyLaunch() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Your data could not be opened, so this session is temporary. Nothing you enter now will be saved."].exists)
    }

    func testEveryTabOpens() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected)
    }

    /// Every settings screen, opened once. A crash on entering one of these is
    /// exactly the kind of thing no unit test can see.
    func testEverySettingsScreenOpens() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()

        let settings = app.navigationBars["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        let rows = ["Jobs", "Working schedule", "Fields", "Holidays", "Export", "iCloud", "Backup and data", "Privacy"]
        var opened = 0

        for row in rows {
            let label = app.staticTexts[row].firstMatch
            guard label.exists, label.isHittable else { continue }
            label.tap()

            // Coming back is the assertion: if the screen had crashed there
            // would be no back button to find.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5), "\(row) did not open")
            back.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5), "could not get back from \(row)")
            opened += 1
        }

        // Rows are skipped when a feature is switched off, and the list scrolls,
        // so not every one is reachable. Finding none at all means the rows
        // stopped being exposed the way this test looks for them, which would
        // otherwise turn the whole test into a no-op that always passes.
        XCTAssertGreaterThanOrEqual(opened, 3, "no settings rows were reachable")
    }

    /// The one flow the app exists for: open a day, save it, come back.
    func testADayOpensAndSaves() {
        let app = XCUIApplication.hours()
        app.launch()

        let today = app.buttons["day-\(Self.todayKey)"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today's cell is not on screen")
        today.tap()

        let save = app.buttons["day-editor-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the day editor did not open")
        save.tap()

        // Deliberately not asserting what was stored. A weekday opens
        // pre-filled from the schedule and a Sunday opens blank, so what a save
        // leaves behind depends on the day the test happens to run — while
        // "the editor opened and closed again" is true every day of the week.
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 5))
        XCTAssertFalse(save.exists, "the editor stayed open after saving")
    }

    /// `yyyyMMdd` for today, the same key the calendar cells are identified by.
    private static var todayKey: Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }
}

extension XCUIApplication {
    /// An app told to start from nothing: its own empty store, default
    /// settings, no running clock. Without this a test would read whatever is
    /// on the machine running it, and would write to it.
    static func hours() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hours-ui-testing"]
        return app
    }
}
