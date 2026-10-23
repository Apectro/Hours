import XCTest

/// Extra work, end to end on the seeded site: a job written with a new item
/// counted up, listed under the day in progress, left out of the report to
/// the boss until it is ticked finished, then in it and summed.
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

        // Material is the one section a new job opens on; the others are
        // closed under their headers.
        let newItem = app.buttons["extra-work-new-item"]
        if !newItem.waitForExistence(timeout: 2) {
            app.buttons["extra-work-section-material"].tap()
        }
        XCTAssertTrue(newItem.waitForExistence(timeout: 5), "Material should offer New item…")
        XCTAssertFalse(app.buttons["extra-work-hours-toggle"].exists, "Time on this job starts closed")
        newItem.tap()
        let name = app.textFields["extra-work-item-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New item… should ask for a name")
        name.tap()
        name.typeText("Emergency light")
        app.buttons["extra-work-item-done"].tap()

        let plus = app.buttons["extra-work-plus-0"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the new item should be a line with a stepper")
        plus.tap()
        plus.tap()
        XCTAssertEqual(app.buttons["extra-work-quantity-0"].label.isEmpty, false)

        // One time for the job, and who was on it: the day's crew chosen.
        let timeHeader = app.buttons["extra-work-section-time"]
        for _ in 0..<3 where !timeHeader.isHittable { app.swipeUp() }
        timeHeader.tap()
        let addTime = app.buttons["extra-work-hours-toggle"]
        XCTAssertTrue(addTime.waitForExistence(timeout: 5), "the time section should open")
        addTime.tap()
        let more = app.buttons["extra-work-time-plus"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "one stepper for the job's time")
        for _ in 0..<4 { more.tap() }
        let firstPerson = app.buttons["extra-work-person-0"]
        XCTAssertTrue(firstPerson.waitForExistence(timeout: 5), "the day's crew as chips")
        XCTAssertTrue(firstPerson.isSelected, "someone is on the job when the time is added")

        app.buttons["extra-work-save"].tap()
        let job = app.buttons["extra-work-job-0"]
        XCTAssertTrue(job.waitForExistence(timeout: 5), "the job should be listed under the day")

        // A new job is in progress: its checkmark is not ticked.
        let tick = app.buttons["extra-work-tick-0"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "the job should have its checkmark")
        XCTAssertFalse(tick.isSelected, "a new job starts in progress")

        // In progress, it is easy to find on the report, and not in it.
        app.buttons["site-extra-work-report"].tap()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 5), "the report did not open")
        XCTAssertTrue(app.buttons["extra-work-in-progress-0"].waitForExistence(timeout: 5),
                      "a job in progress is listed at the top")
        XCTAssertFalse(app.buttons["extra-work-report-job-0"].exists, "the report leaves out jobs in progress")
        let share = app.buttons["extra-work-report-share-pdf"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "the report should offer Send report · PDF")
        XCTAssertFalse(share.isEnabled, "nothing finished, nothing to send")
        app.buttons["extra-work-report-done"].tap()

        // Ticked, it is finished.
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        for _ in 0..<4 where !tick.isHittable { app.swipeUp() }
        tick.tap()
        let ticked = NSPredicate(format: "isSelected == true")
        expectation(for: ticked, evaluatedWith: app.buttons["extra-work-tick-0"])
        waitForExpectations(timeout: 5)

        // And now it is in the report, its material summed.
        app.buttons["site-extra-work-report"].tap()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 5), "the report did not open")
        XCTAssertTrue(app.buttons["extra-work-report-job-0"].waitForExistence(timeout: 5), "a finished job is reported")
        XCTAssertFalse(app.buttons["extra-work-in-progress-0"].exists, "nothing is in progress any more")
        XCTAssertTrue(app.descendants(matching: .any)["extra-work-total-0"].waitForExistence(timeout: 5),
                      "the report should sum the material")
        XCTAssertTrue(share.isEnabled, "a report with a finished job can be sent")
        app.buttons["extra-work-report-done"].tap()
    }
}
