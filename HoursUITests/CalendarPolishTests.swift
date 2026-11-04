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
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        // Under the month, in a list that creates its rows as they come on
        // screen: scrolled to first.
        app.bringToScreen(export)
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Export is not under the month")
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
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.bringToScreen(reopen)
        XCTAssertTrue(reopen.waitForExistence(timeout: 5), "a closed month must say so under Today")
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

        // Now with an edit: "Allowance, km, note…", then the day stops
        // counting.
        XCTAssertTrue(app.openTodaysEditor().waitForExistence(timeout: 10))
        let more = app.buttons["day-editor-more"]
        for _ in 0..<6 where !(more.exists && more.isHittable) { app.swipeUp() }
        XCTAssertTrue(more.isHittable, "the editor has no row for the extras")
        more.tap()
        let count = app.switches["day-editor-count-day"]
        for _ in 0..<4 where !(count.exists && count.isHittable) { app.swipeUp() }
        XCTAssertTrue(count.isHittable, "the extras did not open")
        // A tap on the middle of a Form toggle lands on its label, which
        // does not flip it; the switch itself sits at the trailing edge.
        let knob = count.switches.firstMatch
        if knob.exists, knob.isHittable {
            knob.tap()
        } else {
            count.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        // Back to the editor, where Cancel is.
        app.buttons["day-extras-done"].firstMatch.tap()

        let cancel = app.buttons["day-editor-cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Done did not return to the editor")
        cancel.tap()
        let discard = app.buttons.matching(identifier: "day-editor-discard").firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel after an edit must ask first")
        discard.tap()
        XCTAssertTrue(disappears(app.buttons["day-editor-save"]), "Discard did not close the editor")
    }

    /// The month's eighth column: a total for each row's week with hours
    /// in it, beside the days it counts (the neighbouring months' too).
    func testTheMonthHasAWeekTotalOnEachRow() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-data"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))

        // The sample data writes the days around today, so today's row has
        // a total; which row that is depends on the date.
        let total = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-week-total-'")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the month has no week totals")
        XCTAssertTrue(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.exists, "today's tile keeps its identifier")
    }

    /// The header at the top of the list: the title with ‹ › beside it and
    /// Month | Week under it. Today is in the toolbar only while today is
    /// not on screen.
    func testTodayShowsOnlyAwayFromTodaysMonth() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))

        let next = app.buttons["calendar-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "no › beside the title")
        XCTAssertTrue(app.buttons["calendar-previous"].firstMatch.exists, "no ‹ beside the title")
        XCTAssertTrue(app.segmentedControls.matching(identifier: "calendar-mode").firstMatch.exists, "no Month | Week")
        let todayButton = app.buttons["calendar-today"].firstMatch
        XCTAssertFalse(todayButton.exists, "Today is hidden on this month")

        next.tap()
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5), "Today is not offered on next month")
        todayButton.tap()
        XCTAssertTrue(disappears(todayButton), "Today stayed after coming back")
        XCTAssertTrue(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Month | Week under the title: the week's tiles, its total and its
    /// list; the arrows page by the week; back to Month again.
    func testTheWeekShowsItsTilesTotalAndDays() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-data"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))

        let mode = app.segmentedControls.matching(identifier: "calendar-mode").firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "no Month | Week control")
        XCTAssertEqual(mode.buttons.count, 2)
        mode.buttons.element(boundBy: 1).tap()

        XCTAssertTrue(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.waitForExistence(timeout: 5),
                      "today's tile is not in the week")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "calendar-week-total-0").firstMatch.exists,
                      "the week has no total")
        XCTAssertFalse(app.staticTexts.matching(identifier: "calendar-week-total-1").firstMatch.exists,
                       "a week is one row")

        // The sample data writes the days around today: the week has rows.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calendar-week-row-'")).firstMatch
        app.bringToScreen(row)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the week has no list of days")
        row.tap()
        XCTAssertTrue(app.screen("screen-calendar-day").waitForExistence(timeout: 5), "a row did not open its day")
        app.closeDaySheet()

        // A week on, today is not on screen; Today brings it back.
        app.swipeDown()
        app.swipeDown()
        app.buttons["calendar-next"].firstMatch.tap()
        XCTAssertFalse(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.waitForExistence(timeout: 2),
                       "next did not page the week")
        let todayButton = app.buttons["calendar-today"].firstMatch
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5), "Today is not offered on another week")
        todayButton.tap()
        XCTAssertTrue(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.waitForExistence(timeout: 5),
                      "Today did not come back to this week")

        mode.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(disappears(row), "Month kept the week's list")
    }
}
