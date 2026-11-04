import XCTest

/// Swipe actions beyond Missing (1.3): the system's own, as round tinted
/// buttons with a word under each. A shortcut beside the menus and buttons
/// that were already there.
final class SwipeActionsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Sites › swipe › Archive moves the site under Archived; there, a swipe
    /// › Unarchive brings it back. Nothing is asked: nothing is lost.
    func testASiteIsArchivedAndBroughtBackWithASwipe() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()

        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.swipeLeft()
        let archive = app.buttons["site-card-swipe-archive"].firstMatch
        XCTAssertTrue(archive.waitForExistence(timeout: 5), "a swipe on a site should offer Archive")
        archive.tap()

        XCTAssertTrue(waitUntilGone(card, timeout: 5), "the archived site leaves the active list")
        let archived = app.buttons["sites-archived"].firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5), "an archived site shows the Archived row")
        archived.tap()

        let site = app.buttons["sites-archived-site"].firstMatch
        XCTAssertTrue(site.waitForExistence(timeout: 5), "the site is under Archived")
        site.swipeLeft()
        let unarchive = app.buttons["sites-archived-site-swipe-unarchive"].firstMatch
        XCTAssertTrue(unarchive.waitForExistence(timeout: 5), "a swipe on an archived site should offer Unarchive")
        unarchive.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["site-card"].firstMatch.waitForExistence(timeout: 5), "the site is back among the active ones")
    }
}
