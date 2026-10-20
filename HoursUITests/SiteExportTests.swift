import XCTest

/// The director's sheet: a site's month, one column per person.
///
/// Starts from the seeded site (`SampleData.seedSite`), which has the 3rd and
/// 4th of last month written up with you, Ivan and Marko all there. The export
/// opens on last month. Run unpaid: the preview is free, only the file is Pro.
final class SiteExportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSiteExportPreviewShowsEveryone() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let export = app.buttons["site-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the site has no Export button")
        export.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the site export did not open")

        // One column per person, you first. No name is set in a UI test run,
        // so your column says "You".
        let headings = app.staticTexts.matching(identifier: "export-preview-heading")
        XCTAssertTrue(headings.firstMatch.waitForExistence(timeout: 5), "the preview has no headings")
        let titles = headings.allElementsBoundByIndex.map(\.label)
        for person in ["You", "Ivan", "Marko"] {
            XCTAssertTrue(titles.contains(person), "\(person) is missing from the sheet's columns: \(titles)")
        }

        // And the month's totals at the bottom.
        let summaries = app.staticTexts.matching(identifier: "export-preview-summary")
        XCTAssertTrue(summaries.firstMatch.waitForExistence(timeout: 5), "the preview has no summary rows")
        let labels = summaries.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains("Month total"), "there is no Month total row: \(labels)")
    }
}
