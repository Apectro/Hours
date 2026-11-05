import XCTest

/// Days nobody worked on a site (2026-11-05): the red "N not written" opens
/// the days with why nobody worked, a day's Undo brings it back, and a
/// paused site says "Paused" instead of a count.
///
/// The seeded site (`-hours-sample-site`) with `-hours-site-missing-days`
/// expects a day on every day of the week and has only yesterday written,
/// so every day of this month before yesterday is not written. On the 1st
/// and 2nd there is no such day, and the tests that need one skip.
final class NoWorkUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private var dayOfMonth: Int { Calendar.current.component(.day, from: Date()) }

    /// `yyyyMMdd` for the 1st of this month: not written, by the seeding.
    private var firstOfMonthKey: Int {
        let parts = Calendar.current.dateComponents([.year, .month], from: Date())
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + 1
    }

    private func launchOnSites(needsMissingDays: Bool = true) throws -> XCUIApplication {
        if needsMissingDays, dayOfMonth < 3 {
            throw XCTSkip("No day of this month before yesterday to be not written yet.")
        }
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-site-missing-days"]
        app.launch()
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "site-card").firstMatch.waitForExistence(timeout: 5), "the seeded site has no card")
        return app
    }

    /// The card's red count opens the sheet.
    private func openSheet(_ app: XCUIApplication) -> XCUIElement {
        let count = app.buttons.matching(identifier: "site-card-not-written").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "the site shows no red count")
        let sheet = app.screen("site-no-work-sheet").firstMatch
        XCTAssertTrue(tapUntil(count, shows: sheet), "tapping the count did not open the days")
        return sheet
    }

    private func done(_ app: XCUIApplication, sheet: XCUIElement) {
        app.buttons.matching(identifier: "site-no-work-done").firstMatch.tap()
        XCTAssertTrue(waitUntilGone(sheet), "the sheet did not close")
    }

    /// "All N" › No work: every day listed has Undo, and the card no longer
    /// counts any.
    func testAllDaysAreMarkedNoWorkFromTheCard() throws {
        let app = try launchOnSites()
        let sheet = openSheet(app)

        let all = app.buttons.matching(identifier: "site-no-work-all").firstMatch
        let noWork = app.buttons.matching(identifier: "site-no-work-all-noWork").firstMatch
        XCTAssertTrue(tapUntil(all, shows: noWork), "All did not offer the reasons")
        noWork.tap()

        let undo = app.buttons.matching(identifier: "site-no-work-undo-\(firstOfMonthKey)").firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the 1st was not marked")
        XCTAssertTrue(waitUntilGone(all), "All is still offered with nothing left")
        done(app, sheet: sheet)

        XCTAssertTrue(
            waitUntilGone(app.buttons.matching(identifier: "site-card-not-written").firstMatch),
            "the card still counts days not written"
        )
    }

    /// One day marked from the sheet, then Undo on that day's own screen:
    /// the count is back where it was.
    func testUndoOnTheDayBringsTheCountBack() throws {
        let app = try launchOnSites()
        let count = app.buttons.matching(identifier: "site-card-not-written").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let before = count.label
        let sheet = openSheet(app)

        let key = firstOfMonthKey
        let row = app.buttons.matching(identifier: "site-no-work-day-\(key)").firstMatch
        let dayOff = app.buttons.matching(identifier: "site-no-work-\(key)-dayOff").firstMatch
        XCTAssertTrue(tapUntil(row, shows: dayOff), "the day did not offer the reasons")
        dayOff.tap()
        XCTAssertTrue(
            app.buttons.matching(identifier: "site-no-work-undo-\(key)").firstMatch.waitForExistence(timeout: 5),
            "the day was not marked"
        )
        done(app, sheet: sheet)

        // One fewer, or none left.
        let fewer = NSPredicate(format: "exists == false OR label != %@", before)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: fewer, object: count)], timeout: 5), .completed)

        // The site, its 1st, and Undo there.
        app.buttons.matching(identifier: "site-card").firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))
        let day = app.buttons.matching(identifier: "site-overview-day-\(key)").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "the 1st is not in the site's month")
        let undo = app.buttons.matching(identifier: "site-day-no-work-undo").firstMatch
        XCTAssertTrue(tapUntil(day, shows: undo), "the day shows no Undo for no work")
        undo.tap()
        XCTAssertTrue(waitUntilGone(undo), "Undo did not take the no work back")

        // Back to the site, then to the list.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let again = app.buttons.matching(identifier: "site-card-not-written").firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5), "the count did not come back")
        XCTAssertEqual(again.label, before)
    }

    /// Site settings › Paused: the card says "Paused" and counts nothing.
    func testPausingASiteShowsPausedOnTheCard() throws {
        let app = try launchOnSites(needsMissingDays: false)
        app.buttons.matching(identifier: "site-card").firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))

        let menu = app.buttons.matching(identifier: "site-menu").firstMatch
        let edit = app.buttons.matching(identifier: "site-edit").firstMatch
        XCTAssertTrue(tapUntil(menu, shows: edit), "the site's menu did not open")
        edit.tap()

        let paused = app.switches["site-editor-paused"].firstMatch
        XCTAssertTrue(scrollTo(paused, in: app), "Site settings have no Paused switch")
        XCTAssertTrue(flip(paused), "Paused did not switch on")
        XCTAssertTrue(app.descendants(matching: .any)["site-editor-paused-from"].firstMatch.waitForExistence(timeout: 5), "no From date")

        let save = app.buttons.matching(identifier: "site-editor-save").firstMatch
        save.tap()
        XCTAssertTrue(waitUntilGone(save), "the settings did not close")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "site-card-paused").firstMatch.waitForExistence(timeout: 5),
            "the card does not say Paused"
        )
        XCTAssertFalse(app.buttons.matching(identifier: "site-card-not-written").firstMatch.exists)
    }
}
