import XCTest
import UIKit

/// Signing full screen (1.3): the crew sign-off's Sign opens a pad over the
/// whole screen, turned to landscape on a phone; a stroke enables Done, Clear
/// empties it, and Done signs and comes back in portrait.
final class SignaturePadUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Waits, a bounded time, for the window to be wider than tall or not.
    @discardableResult
    private func waitForWindow(landscape: Bool, _ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let frame = window.frame
            if (frame.width > frame.height) == landscape { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let frame = window.frame
        return (frame.width > frame.height) == landscape
    }

    private func draw(on canvas: XCUIElement) {
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6))
        let middle = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: middle)
        middle.press(forDuration: 0.1, thenDragTo: end)
    }

    func testSigningIsFullScreenInLandscapeAndComesBackInPortrait() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 10), "the site's page did not open")
        XCTAssertTrue(app.tapSiteRow("site-overview-sign-off"), "the site's page should have a Sign-off row")
        XCTAssertTrue(app.screen("screen-sign-off").waitForExistence(timeout: 10), "the sign-off did not open")

        let person = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sign-off-person-")).firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5), "the sample site has people to sign")
        let open = app.buttons["signature-open"].firstMatch
        XCTAssertTrue(tapUntil(person, shows: open), "a person's month should open with Sign")
        if isPhone { XCTAssertTrue(waitForWindow(landscape: false, app), "the sheet is in portrait") }

        let canvas = app.descendants(matching: .any)["signature-canvas"].firstMatch
        XCTAssertTrue(tapUntil(open, shows: canvas), "Sign should open the pad")
        if isPhone {
            // The pad says when the app lays it out wider than tall.
            XCTAssertTrue(app.descendants(matching: .any)["signature-pad-wide"].firstMatch.waitForExistence(timeout: 8),
                          "a phone signs in landscape")
        }
        // Full screen: the pad is (nearly) as wide as the window, and most of its height.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(canvas.frame.width, window.width * 0.8, "the pad fills the width: \(canvas.frame) in \(window)")
        XCTAssertGreaterThan(canvas.frame.height, window.height * 0.5, "the pad fills the height: \(canvas.frame) in \(window)")
        XCTAssertTrue(app.buttons["signature-pad-cancel"].firstMatch.exists, "the pad has its own Cancel")

        let done = app.buttons["signature-sign"].firstMatch
        let clear = app.buttons["signature-clear"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertFalse(done.isEnabled, "nothing drawn, nothing to sign")
        XCTAssertFalse(clear.isEnabled, "nothing drawn, nothing to clear")

        draw(on: canvas)
        XCTAssertTrue(done.isEnabled, "a stroke is a signature")
        XCTAssertTrue(clear.isEnabled)

        clear.tap()
        XCTAssertFalse(done.isEnabled, "Clear empties the pad")
        XCTAssertFalse(clear.isEnabled)

        draw(on: canvas)
        XCTAssertTrue(done.isEnabled)
        done.tap()

        XCTAssertTrue(waitUntilGone(canvas, timeout: 8), "Done closes the pad")
        XCTAssertTrue(waitUntilGone(open, timeout: 8), "and the person's month, signed")
        XCTAssertTrue(app.screen("screen-sign-off").waitForExistence(timeout: 5), "back on the sign-off list")
        if isPhone {
            XCTAssertTrue(waitForWindow(landscape: false, app), "signed, the phone is back in portrait")
        }
    }
}
