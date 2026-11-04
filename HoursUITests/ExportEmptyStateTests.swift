import XCTest

/// An export with nothing to show says one thing and offers one button
/// (polish, 2026-11): "Show empty days too" turns the setting on right there,
/// and the sheet appears.
final class ExportEmptyStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testShowEmptyDaysTooFillsAnEmptyExport() {
        let app = XCUIApplication.hours()
        app.launch()

        let export = app.buttons["calendar-export"]
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.bringToScreen(export)
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Export is not under the month")
        export.tap()
        XCTAssertTrue(app.screen("screen-export").waitForExistence(timeout: 10))

        // A store with nothing in it, and empty days off in Sheet options:
        // nothing to show.
        let options = app.buttons.matching(identifier: "export-this-sheet").firstMatch
        let emptyDays = app.switches.matching(identifier: "export-include-empty-days").firstMatch
        XCTAssertTrue(tapUntil(options, shows: emptyDays), "Sheet options did not open")
        if (emptyDays.value as? String) == "1" { flip(emptyDays) }
        XCTAssertEqual(emptyDays.value as? String, "0", "empty days are still on")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntilGone(emptyDays), "Sheet options did not close")

        let show = app.buttons.matching(identifier: "export-show-empty-days").firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10), "the empty export offers no way to show empty days")
        let bar = app.buttons.matching(identifier: "export-format-pdf").firstMatch
        XCTAssertTrue(app.tapAboveBottomBar(show, bar: bar), "Show empty days too could not be tapped")

        XCTAssertTrue(waitUntilGone(show, timeout: 10), "the empty state stayed after showing empty days")
    }
}
