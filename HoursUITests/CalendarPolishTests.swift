import XCTest

/// The calendar's monthly jobs where months are: Export from its own button,
/// stepping the range inside Export, reopening a closed month without going
/// to Settings, and the day editor not losing an edit to Cancel.
final class CalendarPolishTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Gone, waited for: `waitForExistence` returns at once while an element
    /// is still animating away.
    private func disappears(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testExportStepsBackAMonthAndNotPastToday() {
        let app = XCUIApplication.hours()
        app.launch()

        let export = app.buttons["calendar-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10), "Export is not in the calendar's toolbar")
        export.tap()
        XCTAssertTrue(app.screen("screen-export").waitForExistence(timeout: 10))

        // Opened on this month: nothing after it to step to.
        let next = app.buttons["period-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "the range has no arrows")
        XCTAssertFalse(next.isEnabled, "Export must not step into a month that has not started")

        app.buttons["period-previous"].tap()
        XCTAssertTrue(next.isEnabled, "back a month, forward is open again")

        app.buttons["export-done"].tap()
        XCTAssertTrue(disappears(app.screen("screen-export")), "Done did not close Export")
    }

    func testAClosedMonthReopensFromTheCalendar() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-closed-month"]
        app.launch()

        let reopen = app.buttons["calendar-closed-reopen"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 10), "a closed month must say so above the grid")
        reopen.tap()

        // A confirmation dialog can show its buttons twice in the tree (the
        // sheet and its popover form); either one does the same.
        let confirm = app.buttons.matching(identifier: "calendar-reopen-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "reopening is asked once more")
        confirm.tap()

        XCTAssertTrue(disappears(reopen), "the notice stayed after reopening")
    }

    func testCancelAfterAnEditAsksBeforeDiscarding() {
        let app = XCUIApplication.hours()
        app.launch()

        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the day editor did not open")

        // Cancel straight away: nothing changed, so nothing is asked.
        app.buttons["day-editor-cancel"].tap()
        XCTAssertFalse(app.buttons["day-editor-discard"].waitForExistence(timeout: 2), "an untouched day asked to discard")
        XCTAssertTrue(disappears(save), "Cancel on an untouched day did not close it")

        // Now with an edit: "More", then the day stops counting.
        XCTAssertTrue(app.openTodaysEditor().waitForExistence(timeout: 10))
        let more = app.buttons["day-editor-more"]
        for _ in 0..<6 where !(more.exists && more.isHittable) { app.swipeUp() }
        XCTAssertTrue(more.isHittable, "the editor has no More row")
        more.tap()
        let count = app.switches["day-editor-count-day"]
        for _ in 0..<4 where !(count.exists && count.isHittable) { app.swipeUp() }
        XCTAssertTrue(count.isHittable, "More did not open")
        // A tap on the middle of a Form toggle lands on its label, which
        // does not flip it; the switch itself sits at the trailing edge.
        let knob = count.switches.firstMatch
        if knob.exists, knob.isHittable {
            knob.tap()
        } else {
            count.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }

        app.buttons["day-editor-cancel"].tap()
        let discard = app.buttons.matching(identifier: "day-editor-discard").firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel after an edit must ask first")
        discard.tap()
        XCTAssertTrue(disappears(app.buttons["day-editor-save"]), "Discard did not close the editor")
    }
}
