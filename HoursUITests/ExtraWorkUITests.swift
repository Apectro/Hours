import XCTest

/// Extra work, end to end on the seeded site: a job written with a new item
/// counted up, listed under the day, and summed in the report.
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

        app.buttons["extra-work-new-item"].tap()
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

        app.buttons["extra-work-save"].tap()
        let job = app.buttons["extra-work-job-0"]
        XCTAssertTrue(job.waitForExistence(timeout: 5), "the job should be listed under the day")

        app.buttons["site-extra-work-report"].tap()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 5), "the report did not open")
        XCTAssertTrue(app.descendants(matching: .any)["extra-work-total-0"].waitForExistence(timeout: 5),
                      "the report should sum the material")
        let share = app.buttons["extra-work-report-share-pdf"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "the report should offer Send to boss · PDF")
        XCTAssertTrue(share.isEnabled, "a report with a job can be sent")
        app.buttons["extra-work-report-done"].tap()
    }
}
