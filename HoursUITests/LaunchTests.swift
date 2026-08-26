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

        XCTAssertTrue(
            app.buttons["day-\(Self.todayKey)"].waitForExistence(timeout: 10),
            "today's cell is not on screen"
        )
        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the day editor did not open")
        save.tap()

        // Deliberately not asserting what was stored. A weekday opens
        // pre-filled from the schedule and a Sunday opens blank, so what a save
        // leaves behind depends on the day the test happens to run — while
        // "the editor opened and closed again" is true every day of the week.
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 5))
        XCTAssertFalse(save.exists, "the editor stayed open after saving")
    }

    /// Adding a second block and removing it again, which used to be a crash
    /// waiting to happen.
    ///
    /// The shift list was keyed by array position while every row bound into
    /// `draft.shifts[index]` and "Remove this block" deleted from that same
    /// array. Removing one renumbered the rest, so SwiftUI kept a view it had
    /// already built and evaluated it against an index past the end of the
    /// array. Nothing in the suite went near this path — the crash would have
    /// happened on a real device, in the middle of editing a real day.
    func testASecondBlockCanBeAddedAndRemoved() {
        let app = XCUIApplication.hours()
        app.launch()

        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the day editor did not open")

        let add = app.buttons["Add another block"]
        guard add.exists || app.scrollViews.otherElements.buttons["Add another block"].exists else {
            // The button only appears once the day has times on it, which
            // depends on the schedule for the weekday the test runs on.
            return
        }
        add.tap()

        let remove = app.buttons["Remove this block"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "a second block did not appear")
        remove.tap()

        // Surviving is the assertion. The editor still being there proves the
        // process did not go down with it.
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the editor did not survive removing a block")
        app.buttons["day-editor-cancel"].tap()
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 5))
    }

    private static var todayKey: Int { XCUIApplication.todayKey }
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

    /// `yyyyMMdd` for today, the same key the calendar cells are identified by.
    static var todayKey: Int {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Opens the editor for today and returns its Save button.
    ///
    /// A tap selects a day; a tap on the day already selected opens the
    /// editor. Today starts selected, so one tap is normally enough — but
    /// which day starts selected is a product decision, so the second tap is
    /// here rather than assumed away. Both callers got this wrong once by
    /// asserting on the first tap alone.
    func openTodaysEditor(timeout: TimeInterval = 10) -> XCUIElement {
        let today = buttons["day-\(Self.todayKey)"]
        if today.waitForExistence(timeout: timeout) {
            today.tap()
            let save = buttons["day-editor-save"]
            if !save.waitForExistence(timeout: 3) { today.tap() }
        }
        return buttons["day-editor-save"]
    }
}
