import XCTest

/// Extra work, end to end on the seeded site: a job written with a new item
/// counted up, listed under the day in progress, left out of the Extra-work
/// report until it is included or ticked finished, then in it and summed.
final class ExtraWorkUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAJobIsWrittenListedAndReported() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let add = app.buttons["extra-work-add"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the day should offer Add extra work")
        add.tap()
        XCTAssertTrue(app.screen("screen-extra-work-editor").waitForExistence(timeout: 5), "the editor did not open")

        let description = app.descendants(matching: .any)["extra-work-description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Emergency lighting")

        // Material offers the items used before and + New.
        let newItem = app.buttons["extra-work-new-item"]
        XCTAssertTrue(newItem.waitForExistence(timeout: 5), "Material should offer + New")
        newItem.tap()
        let name = app.textFields["extra-work-item-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New item… should ask for a name")
        name.tap()
        name.typeText("Emergency light")
        app.buttons["extra-work-item-save"].tap()

        let plus = app.buttons["extra-work-plus-0"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the new item should be a line with a stepper")
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.buttons["extra-work-quantity-0"].label.isEmpty, false)

        // One time for the job, and who was on it: the day's crew chosen.
        // The editor is a form: a list only makes the rows on screen, so
        // scroll to each one lower down before looking for it.
        let addTime = app.buttons["extra-work-hours-toggle"]
        for _ in 0..<4 where !(addTime.exists && addTime.isHittable) { app.swipeUp() }
        XCTAssertTrue(addTime.waitForExistence(timeout: 5), "How long it took should offer Add")
        addTime.tap()
        let more = app.buttons["extra-work-time-plus"]
        for _ in 0..<3 where !(more.exists && more.isHittable) { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 5), "one stepper for the job's time")
        for _ in 0..<4 { more.tap() }
        let firstPerson = app.buttons["extra-work-person-0"]
        for _ in 0..<3 where !firstPerson.exists { app.swipeUp() }
        XCTAssertTrue(firstPerson.waitForExistence(timeout: 5), "the day's crew as rows to tick")
        XCTAssertTrue(firstPerson.isSelected, "someone is on the job when the time is added")

        app.buttons["extra-work-save"].tap()
        let job = app.buttons["extra-work-job-0"]
        XCTAssertTrue(job.waitForExistence(timeout: 5), "the job should be listed under the day")

        // A new job is in progress: its checkmark is not ticked.
        let tick = app.buttons["extra-work-tick-0"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "the job should have its checkmark")
        XCTAssertFalse(tick.isSelected, "a new job starts in progress")
        // The editor's sheet has to be gone, or the back tap lands on its toolbar.
        app.screen("screen-extra-work-editor").waitUntilGone(timeout: 10)

        // In progress, it is not in the report, and the empty report says
        // why: Include them, or Mark finished… to list it with its checkmark.
        // The report is on the site's page (1.2), one back from the day.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSiteExtraWorkReport()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 5), "the report did not open")
        XCTAssertFalse(app.buttons["extra-work-report-job-0"].exists, "the report leaves out jobs in progress")
        let share = app.buttons["extra-work-report-share-pdf"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "the report should offer Send to boss · PDF")
        XCTAssertFalse(share.isEnabled, "nothing finished, nothing to send")
        let moreFormats = app.buttons["extra-work-report-more-formats"]
        XCTAssertTrue(moreFormats.waitForExistence(timeout: 5), "the picture, Excel and CSV are under More formats")
        XCTAssertFalse(moreFormats.isEnabled, "nothing finished, no other format to send")
        let markFinished = app.buttons["extra-work-report-mark-finished"]
        XCTAssertTrue(markFinished.waitForExistence(timeout: 5), "an empty report held back by a job in progress offers Mark finished…")
        XCTAssertTrue(app.buttons["extra-work-report-include-them"].exists, "and Include them")
        markFinished.tap()
        XCTAssertTrue(app.buttons["extra-work-in-progress-0"].waitForExistence(timeout: 5),
                      "Mark finished… lists the job in progress")
        XCTAssertTrue(app.buttons["extra-work-in-progress-tick-0"].exists, "with its checkmark")
        app.buttons["extra-work-report-include-them"].tap()
        XCTAssertTrue(app.buttons["extra-work-report-in-progress-0"].waitForExistence(timeout: 5),
                      "Include them puts the job in the report, as still in progress")
        XCTAssertTrue(share.isEnabled, "a report with a job in it can be sent")
        app.buttons["extra-work-report-done"].tap()
        // The report's sheet has to be gone, or Write today's tap lands on it.
        app.screen("screen-extra-work-report").waitUntilGone(timeout: 10)
        app.openTodayOnSite()

        // Ticked, it is finished. The day is a list: scroll down to the job.
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")
        for _ in 0..<8 where !tick.exists { app.swipeUp() }
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        for _ in 0..<4 where !tick.isHittable { app.swipeUp() }
        // Something can still lie over it for a moment on a slow runner (the
        // report's sheet sliding off): wait until it can be hit.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: tick)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed, "the tick stayed covered")
        // Tapped again only if the first tap was not taken (a slow runner):
        // the tick is checked before every tap, so a taken one is never undone.
        let ticked = NSPredicate(format: "isSelected == true")
        var isTicked = false
        for _ in 0..<2 where !isTicked {
            guard tick.isHittable else { break }
            tick.tap()
            let wait = XCTNSPredicateExpectation(predicate: ticked, object: app.buttons["extra-work-tick-0"])
            isTicked = XCTWaiter().wait(for: [wait], timeout: 5) == .completed
        }
        if !isTicked {
            // Until the cause is known: what lies over the tick after a tap.
            print("TICK-COVERED\n" + app.debugDescription)
        }
        XCTAssertTrue(isTicked, "the tick should mark the job finished")

        // And now it is in the report, its material summed.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.openSiteExtraWorkReport()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 5), "the report did not open")
        XCTAssertTrue(app.buttons["extra-work-report-job-0"].waitForExistence(timeout: 5), "a finished job is reported")
        XCTAssertFalse(app.buttons["extra-work-in-progress-0"].exists, "nothing is in progress any more")
        XCTAssertTrue(app.descendants(matching: .any)["extra-work-total-0"].waitForExistence(timeout: 5),
                      "the report should sum the material")
        XCTAssertTrue(share.isEnabled, "a report with a finished job can be sent")
        XCTAssertTrue(moreFormats.isEnabled, "and sent in the other formats")
        moreFormats.tap()
        XCTAssertTrue(app.buttons["extra-work-send-picture"].waitForExistence(timeout: 5),
                      "More formats offers Send as picture, for a chat")
        // Closes the menu without choosing anything.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(app.buttons["extra-work-report-done"].waitForExistence(timeout: 5))
        app.buttons["extra-work-report-done"].tap()
    }
}

private extension XCUIApplication {
    /// The site page's Extra work row, further down the list: a list only
    /// makes the rows on screen, so scroll to it first.
    func openSiteExtraWorkReport() {
        XCTAssertTrue(screen("screen-site").waitForExistence(timeout: 5), "back should lead to the site's page")
        tapSiteRow("site-extra-work-report")
    }
}
