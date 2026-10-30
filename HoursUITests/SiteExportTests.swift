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
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5), "the site did not open")

        // The site's Sheet button, at the bottom of its page.
        let export = app.buttons["site-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the site has no Sheet button")
        export.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the site export did not open")

        // The screen previews the PDF's first page. Excel opens the
        // workbook ready to send, previewed as its table: unpaid, nothing is
        // written and Send… is locked, but the sheet is shown. With Pro the
        // name would be asked for first; any answer will do.
        XCTAssertTrue(app.descendants(matching: .any)["export-preview-page"].waitForExistence(timeout: 10), "the PDF has no page preview")
        let excel = app.buttons["export-format-xlsx"]
        XCTAssertTrue(excel.waitForExistence(timeout: 5), "there is no Excel button")
        excel.tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.buttons.matching(identifier: "export-share").firstMatch.waitForExistence(timeout: 10),
                      "Excel should open the file ready to send")

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

    /// One sheet for two sites (1.2): a second site's chip ticked, and the
    /// preview's page is the sheet for both.
    func testASecondSiteJoinsTheSheet() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-second-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        // The site's Sheet button, under its name (the "…" menu is gone).
        let export = app.buttons.matching(identifier: "site-export").firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the site has no Sheet button")
        export.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the site export did not open")

        let page = app.descendants(matching: .any).matching(identifier: "export-preview-page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the PDF has no page preview")
        XCTAssertFalse((page.value as? String ?? "").contains("Trg Pravde"), "the sheet starts on one site")

        // WHICH SITES: the second site's chip, ticked.
        let other = app.buttons.matching(identifier: "export-sheet-site-0").firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "the second site has no chip")
        other.tap()

        // The page is drawn again for both: its title names them in order.
        let both = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@", "Kaiserstrasse 12", "Trg Pravde")
        expectation(for: both, evaluatedWith: page)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(page.value as? String, "Kaiserstrasse 12 · Trg Pravde")
    }

    /// The Sites list offers each month's sheet: it opens on a crew sheet
    /// with the sites worked that month already ticked.
    func testTheSitesListOpensAMonthsSheet() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-second-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let month = app.buttons.matching(identifier: "sites-month-sheet").firstMatch
        for _ in 0..<4 where !(month.exists && month.isHittable) { app.swipeUp() }
        XCTAssertTrue(month.isHittable, "the Sites list offers no month's sheet")
        month.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the month's sheet did not open")

        // Only the site with days that month: Trg Pravde has none.
        let page = app.descendants(matching: .any).matching(identifier: "export-preview-page").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the PDF has no page preview")
        let title = page.value as? String ?? ""
        XCTAssertTrue(title.contains("Kaiserstrasse 12"), "the sheet should be the seeded site's")
        XCTAssertFalse(title.contains("Trg Pravde"), "a site with nothing that month is not ticked")
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
        let crewItem = app.buttons.matching(identifier: "site-crew").firstMatch
        XCTAssertTrue(crewItem.waitForExistence(timeout: 5), "the site has no Crew button")
        crewItem.tap()
        if !app.screen("screen-crew").waitForExistence(timeout: 5) {
            // What was on screen instead, for the log.
            print(app.debugDescription)
        }
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "the crew list did not open")

        // Ivan's row opens his month (1.2). A name is the person's own, not
        // a translated label.
        let ivan = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "crew-member", "Ivan")).firstMatch
        XCTAssertTrue(ivan.waitForExistence(timeout: 5), "Ivan has no row")
        ivan.tap()

        // It opens on this month. The seed wrote yesterday, which on the
        // first of a month was last month, so step back once if need be.
        let share = app.buttons.matching(identifier: "crew-sheet-share").firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Ivan's month has no Share button")
        let enabled = NSPredicate(format: "isEnabled == true")
        let thisMonth = XCTNSPredicateExpectation(predicate: enabled, object: share)
        if XCTWaiter().wait(for: [thisMonth], timeout: 5) != .completed {
            let previous = app.buttons.matching(identifier: "period-previous").firstMatch
            XCTAssertTrue(previous.waitForExistence(timeout: 5), "Ivan's month has no month stepper")
            previous.tap()
        }
        expectation(for: enabled, evaluatedWith: share)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons.matching(identifier: "crew-sheet-sign").firstMatch.exists, "Ivan's month has no Sign the month")

        // The page itself, under the days.
        let page = app.descendants(matching: .any).matching(identifier: "export-preview-page").firstMatch
        for _ in 0..<4 where !page.exists { app.swipeUp() }
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Ivan's sheet has no page preview")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "Back did not go back to the crew")
    }
}
