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
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "someone with no holidays was not offered them")
        app.buttons["public-holiday-offer-dismiss"].tap()
        XCTAssertFalse(offer.waitForExistence(timeout: 2), "the offer stayed after Not now")
    }

    func testAddingACountrysHolidaysFromTheOffer() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.buttons["public-holiday-offer-choose"].waitForExistence(timeout: 10))
        app.buttons["public-holiday-offer-choose"].tap()

        let austria = app.buttons["public-holidays-country-at"]
        XCTAssertTrue(austria.waitForExistence(timeout: 5), "the countries were not listed")
        austria.tap()

        let add = app.buttons["public-holidays-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the preview did not open")
        XCTAssertTrue(app.buttons["public-holidays-item-christmas"].exists)
        add.tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["public-holiday-offer"].waitForExistence(timeout: 2),
            "the offer stayed after the holidays were added"
        )
    }
}
