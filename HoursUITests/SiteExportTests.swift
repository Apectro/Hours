import XCTest

/// The director's sheet: a site's month, one group of columns per person.
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

        // Export is in the toolbar's menu, with Crew and Edit.
        let more = app.buttons["site-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the site has no menu")
        more.tap()
        let export = app.buttons["site-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the site's menu has no Export")
        export.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the site export did not open")

        // The screen opens on the PDF, previewed as its first page. The
        // workbook's preview is the table, so switch to it.
        XCTAssertTrue(app.descendants(matching: .any)["export-preview-page"].waitForExistence(timeout: 10), "the PDF has no page preview")
        let excel = app.buttons["export-format-xlsx"]
        XCTAssertTrue(excel.waitForExistence(timeout: 5), "there is no Excel format card")
        excel.tap()

        // One pair of columns per person, you first, under the person's name.
        // No name is set in a UI test run, so yours says "You".
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

    /// A crew member's own sheet, from the crew list: their month as the
    /// page they are handed, before it is shared.
    func testACrewMembersSheetOpensOnItsPage() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        let more = app.buttons.matching(identifier: "site-more").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the site has no menu")
        more.tap()
        let crewItem = app.buttons.matching(identifier: "site-crew").firstMatch
        XCTAssertTrue(crewItem.waitForExistence(timeout: 5), "the site's menu has no Crew")
        crewItem.tap()
        if !app.screen("screen-crew").waitForExistence(timeout: 5) {
            // What was on screen instead, for the log.
            print(app.debugDescription)
        }
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "the crew list did not open")

        // A name is the person's own, not a translated label.
        let share = app.buttons.matching(identifier: "crew-share-Ivan").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5), "Ivan has no Share sheet button")
        share.tap()

        // It opens on this month. The seed wrote yesterday, which on the
        // first of a month was last month, so step back once if need be.
        let page = app.descendants(matching: .any).matching(identifier: "export-preview-page").firstMatch
        if !page.waitForExistence(timeout: 10) {
            let previous = app.buttons.matching(identifier: "period-previous").firstMatch
            XCTAssertTrue(previous.waitForExistence(timeout: 5), "the sheet has no month stepper")
            previous.tap()
        }
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Ivan's sheet has no page preview")
        XCTAssertTrue(app.buttons.matching(identifier: "export-share").firstMatch.exists, "the sheet has no share button")

        let done = app.buttons.matching(identifier: "crew-sheet-done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "Done did not go back to the crew")
    }
}
