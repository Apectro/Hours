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

        // Row titles, not section headers: "Export" is a heading and tapping it
        // would go nowhere. Rows behind a switched-off feature are skipped
        // below rather than listed here, since which ones exist depends on the
        // settings the app starts with.
        let rows = [
            "Working schedule", "Jobs", "Calculation",
            "Fields", "Day types", "Reminders", "Holidays",
            "Theme", "Export options",
            "iCloud", "Backup and data", "Privacy",
        ]
        var opened = 0

        for row in rows {
            let label = app.staticTexts[row].firstMatch
            guard label.exists, label.isHittable else { continue }
            label.tap()

            // A back button labelled "Settings" is proof both that the screen
            // opened and that it did not crash on the way in. Matched by name
            // rather than by position, so a screen with its own toolbar button
            // does not quietly pass this by being tapped somewhere else.
            let back = app.navigationBars.buttons["Settings"]
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

    /// The one flow the app exists for: open a day, save it, come back. Run
    /// unpaid, so it doubles as the assertion that recording hours is free.
    func testADayOpensAndSaves() {
        let app = XCUIApplication.hours()
        app.launch()

        let today = app.buttons["day-\(Self.todayKey)"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today's cell is not on screen")
        today.tap()

        // A tap selects the day; a tap on the day already selected opens the
        // editor. Today starts selected, so one tap is normally enough — but
        // the second tap is here rather than relying on that, since which day
        // starts selected is a product decision and not this test's subject.
        let save = app.buttons["day-editor-save"]
        if !save.waitForExistence(timeout: 3) { today.tap() }
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
    static func hours(pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hours-ui-testing"]
        // Unpaid by default, so what gets exercised is the app most people
        // open on day one.
        if pro { app.launchArguments += ["-hours-pro"] }
        return app
    }
}
