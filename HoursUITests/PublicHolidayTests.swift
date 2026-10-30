import XCTest

/// The calendar's one-time offer of a country's public holidays.
final class PublicHolidayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheOfferCanBePutAway() {
        let app = XCUIApplication.hours()
        app.launch()

        let offer = app.descendants(matching: .any)["public-holiday-offer"]
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        // Under Today, in a list that creates its rows as they come on screen.
        let dismiss = app.buttons["public-holiday-offer-dismiss"]
        app.bringToScreen(dismiss)
        XCTAssertTrue(offer.waitForExistence(timeout: 5), "someone with no holidays was not offered them")
        dismiss.tap()
        XCTAssertFalse(offer.waitForExistence(timeout: 2), "the offer stayed after Not now")
    }

    func testAddingACountrysHolidaysFromTheOffer() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.bringToScreen(app.buttons["public-holiday-offer-choose"])
        XCTAssertTrue(app.buttons["public-holiday-offer-choose"].waitForExistence(timeout: 5))
        app.buttons["public-holiday-offer-choose"].tap()

        let austria = app.buttons["public-holidays-country-at"]
        XCTAssertTrue(austria.waitForExistence(timeout: 5), "the countries were not listed")
        austria.tap()

        let add = app.buttons["public-holidays-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the preview did not open")
        // The first row: a List only creates the rows on screen, and
        // Christmas sits at the bottom of Austria's thirteen.
        XCTAssertTrue(app.buttons["public-holidays-item-newYear"].exists)
        add.tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["public-holiday-offer"].waitForExistence(timeout: 2),
            "the offer stayed after the holidays were added"
        )
    }
}
