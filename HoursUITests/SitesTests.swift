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

    /// The crew's trailing swipe, on the cell itself: Hide is behind it.
    ///
    /// The long-press menu is exercised in `testCreateSiteAndAddCrew`; this is the swipe
    /// the footer tells people about. It once failed to reveal anything in
    /// CI, while "screen-crew" sat on the List and so on every row inside it.
    func testSwipingACrewRowRevealsHide() {
        let app = XCUIApplication.hours()
        app.launch()
        openCrewOfANewSite(app, named: "Swipe Street 1")

        let newMember = app.textFields["crew-new-name"]
        XCTAssertTrue(newMember.waitForExistence(timeout: 5))
        newMember.tap()
        newMember.typeText("Marko\n")
        // A name is the person's own, not a translated label.
        let cell = app.cells.containing(NSPredicate(format: "label == %@", "Marko")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Marko was not added")
        // The keyboard would take the swipe's room, and focus with it.
        if app.keyboards.count > 0 { app.staticTexts["screen-crew"].firstMatch.tap() }

        // Swipe actions carry their identifier in current iOS releases; the
        // label is the fallback, as this suite runs in English.
        let hide = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "crew-hide", "Hide")).firstMatch
        cell.swipeLeft()
        if !hide.waitForExistence(timeout: 3) {
            // A slower, longer drag from the right of the name, for a
            // simulator that took the first swipe as a scroll.
            let from = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            let to = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            from.press(forDuration: 0.1, thenDragTo: to)
        }
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "the trailing swipe on a crew row did not reveal Hide")
        hide.tap()
        XCTAssertTrue(app.staticTexts["crew-hidden-header"].waitForExistence(timeout: 5), "Hide from the swipe did not hide")
    }

    /// From launch to a new site's crew list.
    private func openCrewOfANewSite(_ app: XCUIApplication, named siteName: String) {
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "the Sites tab did not open")
        app.buttons.matching(identifier: "sites-add").firstMatch.tap()
        let name = app.textFields["site-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the site editor did not open")
        name.tap()
        name.typeText(siteName)
        app.buttons.matching(identifier: "site-editor-save").firstMatch.tap()
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the new site has no card")
        card.tap()
        let more = app.buttons.matching(identifier: "site-more").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the site did not open")
        more.tap()
        let crewItem = app.buttons.matching(identifier: "site-crew").firstMatch
        XCTAssertTrue(crewItem.waitForExistence(timeout: 5), "the site's menu has no Crew")
        crewItem.tap()
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "the crew list did not open")
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
        // Hide from the long-press menu, which every row has. The row's
        // trailing swipe offers the same and has its own test,
        // `testSwipingACrewRowRevealsHide`.
        if app.keyboards.count > 0 { app.staticTexts["You"].tap() }
        app.staticTexts["Marko"].press(forDuration: 1.2)
        let hide = app.buttons["Hide"].firstMatch
        _ = hide.waitForExistence(timeout: 5)
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
