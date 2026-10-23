import XCTest

/// The Sites tab: making a site and putting a crew on it.
///
/// Run unpaid on purpose. The first site is free, with its whole crew, so a
/// paywall appearing anywhere in this flow is itself the failure.
final class SitesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCreateSiteAndAddCrew() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "the Sites tab did not open")

        // A new site, named and saved.
        app.buttons["sites-add"].tap()
        let name = app.textFields["site-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the site editor did not open")
        name.tap()
        name.typeText("Kaiserstrasse 12")
        app.buttons["site-editor-save"].tap()

        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the new site has no card")
        XCTAssertTrue(card.label.contains("Kaiserstrasse 12"), "the card does not carry the site's name: \(card.label)")
        XCTAssertFalse(app.staticTexts["Unlock Zeitkonto Pro"].exists, "the first site must be free")

        // Into the site and on to its crew, which is in the toolbar's menu.
        card.tap()
        let more = app.buttons["site-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the site did not open")
        more.tap()
        let crewItem = app.buttons["site-crew"]
        XCTAssertTrue(crewItem.waitForExistence(timeout: 5), "the site's menu has no Crew")
        crewItem.tap()
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "the crew list did not open")

        // You are always there, before anyone is added.
        XCTAssertTrue(app.staticTexts["You"].exists, "the crew list does not start with you")

        let newMember = app.textFields["crew-new-name"]
        XCTAssertTrue(newMember.waitForExistence(timeout: 5))
        newMember.tap()
        newMember.typeText("Ivan\n")
        XCTAssertTrue(app.staticTexts["Ivan"].waitForExistence(timeout: 5), "Ivan was not added")

        newMember.tap()
        newMember.typeText("Marko\n")
        XCTAssertTrue(app.staticTexts["Marko"].waitForExistence(timeout: 5), "Marko was not added")

        // Hiding keeps Marko, under Hidden, and takes him off the count.
        // The name field keeps the keyboard up for the next name, and a
        // swipe while it is up only puts it away. Put it away first, and
        // swipe again if the first one was spent on it.
        if app.keyboards.count > 0 { app.staticTexts["You"].tap() }
        let hide = app.buttons["Hide"]
        for _ in 0..<2 where !hide.exists {
            app.staticTexts["Marko"].swipeLeft()
            _ = hide.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(hide.exists, "no Hide action on a crew member")
        hide.tap()
        XCTAssertTrue(app.staticTexts["crew-hidden-header"].waitForExistence(timeout: 5), "a hidden member has no Hidden section")
        XCTAssertTrue(app.staticTexts["Marko"].exists, "hiding someone must not remove them")

        // Back to the list: you and one coworker. By the back buttons, which
        // sit first in the bar; their titles are the site's name and a
        // translated word, and either may be shortened to fit.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(more.waitForExistence(timeout: 5), "could not get back to the site")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "could not get back to the list")
        let updated = app.buttons["site-card"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertTrue(
            updated.label.contains("Crew: you + 1 coworker"),
            "the card should count Ivan and not the hidden Marko: \(updated.label)"
        )
    }
}
