import XCTest

extension XCUIApplication {
    /// A new site through the wizard (1.2), "Start fresh": the Sites tab's
    /// New site, the name, then Next through the crew, the usual day and the
    /// extras, and Create site. Ends on the Sites list.
    func createSiteWithWizard(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tab(.sites).waitForExistence(timeout: 10), file: file, line: line)
        tab(.sites).tap()
        XCTAssertTrue(screen("screen-sites").waitForExistence(timeout: 5), "the Sites tab did not open", file: file, line: line)
        buttons.matching(identifier: "sites-add").firstMatch.tap()

        let fresh = buttons["wizard-start-fresh"].firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 5), "the new-site wizard did not open", file: file, line: line)
        fresh.tap()
        wizardNext(file: file, line: line)

        let field = textFields["site-name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the wizard has no name field", file: file, line: line)
        field.tap()
        field.typeText(name)
        // Where, crew, usual day, extras: on to the check.
        for _ in 0..<4 { wizardNext(file: file, line: line) }

        let create = buttons["wizard-create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5), "the wizard did not reach its check", file: file, line: line)
        create.tap()
        XCTAssertTrue(screen("screen-sites").waitForExistence(timeout: 5), "creating did not go back to the list", file: file, line: line)
    }

    /// The wizard's big Next at the bottom.
    func wizardNext(file: StaticString = #filePath, line: UInt = #line) {
        let next = buttons["wizard-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5), "the wizard has no Next", file: file, line: line)
        XCTAssertTrue(next.isEnabled, "Next is not available", file: file, line: line)
        next.tap()
    }

    /// From a site's page (1.2) to today on the site: its big Write today.
    func openTodayOnSite(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(screen("screen-site").waitForExistence(timeout: 10), "the site's page did not open", file: file, line: line)
        let today = buttons.matching(identifier: "site-write-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the site's page has no Write today", file: file, line: line)
        today.tap()
    }
}
