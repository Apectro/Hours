import XCTest

/// A site's address in its settings (1.2): typed, saved, and there again
/// when the settings are opened next. Found by identifier, never by the
/// translated words.
final class SiteAddressUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testATypedAddressIsKeptWithTheSite() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSiteSettings(app)

        let field = addressField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the site's settings have no address field")
        field.tap()
        field.typeText("Kaiserstrasse 12, 10115 Berlin")
        app.buttons.matching(identifier: "site-editor-save").firstMatch.tap()

        openSiteSettings(app, fromSite: true)
        let saved = addressField(app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let value = saved.value as? String ?? ""
        XCTAssertTrue(value.contains("Kaiserstrasse 12, 10115 Berlin"), "the address was not kept: \(value)")
    }

    // MARK: - Helpers

    /// A text field that grows to more lines is a text view underneath.
    private func addressField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "site-address").firstMatch
    }

    private func openSiteSettings(_ app: XCUIApplication, fromSite: Bool = false) {
        if !fromSite {
            XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
            app.tab(.sites).tap()
            let card = app.buttons["site-card"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
            card.tap()
        }
        let more = app.buttons.matching(identifier: "site-more").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the site did not open")
        more.tap()
        let edit = app.buttons.matching(identifier: "site-edit").firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the site's menu has no Edit")
        edit.tap()
        XCTAssertTrue(app.textFields["site-name"].waitForExistence(timeout: 5), "the site's settings did not open")
    }
}
