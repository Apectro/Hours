import XCTest

/// Checking a delivery against Missing › Ordered and a site's defects
/// (1.3), on the seeded site. The simulator has no camera, so the scanner
/// offers its typed-code field and a new defect goes without a photo.
final class DefectsDeliveryUITests: XCTestCase {
    /// The codes `-hours-sample-order` names (`SampleData.orderCodes`): two
    /// junction boxes and 50 m of cable ordered, an emergency light not.
    private let boxCode = "4006381333931"
    private let cableCode = "4006381333948"
    private let lightCode = "4006381333955"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func openSite(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 10), "the site's page did not open")
    }

    /// A code typed and sent with Return, which also puts the keyboard away.
    private func scan(_ code: String, _ app: XCUIApplication) {
        let field = app.textFields["scanner-code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the scanner should offer the typed code")
        field.tap()
        field.typeText(code + "\n")
    }

    // MARK: - The delivery check

    /// Two boxes of two (full), the cable one metre short, an emergency
    /// light nobody ordered: the result lists each where it belongs, saving
    /// says what is still missing, and Missing's tabs follow.
    func testADeliveryIsCheckedFullShortAndExtra() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-sample-order"]
        app.launch()
        openSite(app)
        XCTAssertTrue(app.tapSiteRow("site-missing"), "the site's page should have a Missing row")
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "Missing did not open")

        let states = app.segmentedControls["missing-state"]
        XCTAssertTrue(states.waitForExistence(timeout: 5))
        states.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(states.buttons.element(boundBy: 1).label.contains("2"), "two ordered: \(states.buttons.element(boundBy: 1).label)")

        let check = app.buttons["missing-delivery-check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5), "Ordered should offer Check a delivery")
        check.tap()
        XCTAssertTrue(app.screen("screen-scanner").waitForExistence(timeout: 5), "the scanner did not open")

        scan(boxCode, app)
        scan(boxCode, app)
        scan(cableCode, app)
        // The cable is set to the order, 50 m, and one metre is taken off.
        let minus = app.buttons["delivery-line-0-minus"]
        XCTAssertTrue(minus.waitForExistence(timeout: 5), "a measured item should get a stepper")
        minus.tap()
        scan(lightCode, app)
        XCTAssertTrue(app.descendants(matching: .any)["delivery-here"].label.hasPrefix("2"), "two of two expected are here")

        app.buttons["delivery-done"].tap()
        XCTAssertTrue(app.screen("screen-delivery-result").waitForExistence(timeout: 5), "the result did not open")
        XCTAssertTrue(app.descendants(matching: .any)["delivery-arrived-0"].label.contains("Junction box"), "the boxes all came")
        XCTAssertTrue(app.descendants(matching: .any)["delivery-short-0"].label.contains("Cable"), "the cable is short")
        XCTAssertTrue(app.descendants(matching: .any)["delivery-extra-row-0"].label.contains("Emergency light"), "the light came anyway")

        app.buttons["delivery-save"].tap()
        XCTAssertTrue(app.screen("screen-delivery-saved").waitForExistence(timeout: 5), "saving should say so")
        let message = app.descendants(matching: .any)["delivery-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("1 m Cable NYM 3×1.5"), "the message: \(message.label)")
        XCTAssertTrue(message.label.contains("1 × Emergency light 3h"), "the message: \(message.label)")
        XCTAssertFalse(message.label.contains("Junction box"), "what all came is not missing: \(message.label)")
        XCTAssertTrue(app.buttons["delivery-send"].exists)
        app.buttons["delivery-finish"].tap()

        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5))
        let ordered = states.buttons.element(boundBy: 1)
        XCTAssertTrue(ordered.label.contains("1"), "the cable's last metre stays ordered: \(ordered.label)")
        states.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["missing-delivery-row-0"].waitForExistence(timeout: 5), "the delivery is under Arrived")
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-1"].exists, "the boxes and the 49 m arrived")
        app.buttons["missing-delivery-row-0"].tap()
        XCTAssertTrue(app.screen("screen-delivery-detail").waitForExistence(timeout: 5), "a saved delivery opens read-only")
        app.buttons["delivery-detail-done"].tap()
    }

    // MARK: - Defects

    /// Opens a new defect from the list, where there is no camera.
    private func startDefect(_ app: XCUIApplication) {
        let add = app.buttons["defects-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Defects should offer +")
        add.tap()
        let skip = app.buttons["defect-camera-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "without a camera, a defect can go without a photo")
        skip.tap()
        XCTAssertTrue(app.screen("screen-defect-details").waitForExistence(timeout: 5), "the details did not open")
    }

    private func typeWhat(_ text: String, _ app: XCUIApplication) {
        let what = app.descendants(matching: .any)["defect-what"].firstMatch
        XCTAssertTrue(what.waitForExistence(timeout: 5))
        what.tap()
        what.typeText(text)
    }

    /// Two defects noted without a camera, the second on a lower floor with
    /// the room remembered from the first: listed in the site's floor
    /// order; fixed from the viewer it moves to Fixed; Send the list says
    /// the open one.
    func testDefectsAreGroupedByFloorFixedAndSent() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        XCTAssertTrue(app.tapSiteRow("site-defects"), "the site's page should have a Defects row")
        XCTAssertTrue(app.screen("screen-defects").waitForExistence(timeout: 5), "Defects did not open")

        startDefect(app)
        typeWhat("Socket loose", app)
        app.buttons["defect-floor-2"].tap() // 2nd floor
        let room = app.textFields["defect-room-field"]
        XCTAssertTrue(room.waitForExistence(timeout: 5), "with no rooms yet, the room is typed")
        // The field sits just above Add defect: tapped plainly, with the
        // keyboard up, the tap can land on the button instead.
        XCTAssertTrue(app.tapAboveBottomBar(room, bar: app.buttons["defect-add"]), "the room field could not be reached")
        if !room.waitForExistence(timeout: 3) {
            // Left here until the cause is known: what the screen holds when
            // the room field has gone after being tapped.
            print("ROOM-FIELD-GONE\n" + app.debugDescription)
            XCTFail("the room field went away when tapped")
            return
        }
        room.typeText("Room 4")
        app.buttons["defect-add"].tap()
        XCTAssertTrue(app.buttons["defects-row-0"].waitForExistence(timeout: 5), "the defect should be listed")

        startDefect(app)
        let suggestion = app.buttons["defect-what-chip-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5), "the site's earlier defect is offered")
        typeWhat("Cable not labelled", app)
        app.buttons["defect-floor-0"].tap() // Ground
        let remembered = app.buttons["defect-room-0"]
        XCTAssertTrue(remembered.waitForExistence(timeout: 5), "the room is remembered as a chip")
        XCTAssertTrue(app.tapAboveBottomBar(remembered, bar: app.buttons["defect-add"]))
        app.buttons["defect-add"].tap()

        let first = app.buttons["defects-row-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("Cable not labelled"), "Ground comes before the 2nd floor: \(first.label)")
        XCTAssertTrue(app.buttons["defects-row-1"].label.contains("Socket loose"))
        XCTAssertFalse(app.buttons["defects-row-0"].label.contains("Ivan"), "nobody fixes it while assigning is off")

        first.tap()
        XCTAssertTrue(app.screen("screen-defect-viewer").waitForExistence(timeout: 5), "the viewer did not open")
        app.buttons["defect-mark-fixed"].tap()
        XCTAssertTrue(app.buttons["defect-reopen"].waitForExistence(timeout: 5), "a fixed defect offers Reopen")
        app.buttons["defect-viewer-done"].tap()

        let states = app.segmentedControls["defects-state"]
        XCTAssertTrue(states.waitForExistence(timeout: 5))
        XCTAssertTrue(states.buttons.element(boundBy: 0).label.contains("1"), "one open: \(states.buttons.element(boundBy: 0).label)")
        XCTAssertTrue(states.buttons.element(boundBy: 1).label.contains("1"), "one fixed: \(states.buttons.element(boundBy: 1).label)")
        states.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["defects-row-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["defects-row-0"].label.contains("Cable not labelled"), "the fixed one is under Fixed")
        states.buttons.element(boundBy: 0).tap()

        app.buttons["defects-send"].tap()
        XCTAssertTrue(app.screen("screen-defects-send").waitForExistence(timeout: 5), "Send the list did not open")
        let text = app.descendants(matching: .any)["defects-send-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("Kaiserstrasse 12 · Defects"), "the message: \(text.label)")
        XCTAssertTrue(text.label.contains("1. Socket loose"), "the message: \(text.label)")
        XCTAssertTrue(text.label.contains("2nd floor · Room 4"), "the message: \(text.label)")
        XCTAssertFalse(text.label.contains("Cable not labelled"), "only open: \(text.label)")
        app.switches["defects-send-only-open"].firstMatch.tap()
        XCTAssertTrue(text.label.contains("Cable not labelled"), "with the fixed ones: \(text.label)")
        XCTAssertTrue(app.buttons["defects-send-pdf"].exists)
        XCTAssertTrue(app.buttons["defects-send-message"].exists)
        app.buttons["defects-send-close"].tap()
    }

    /// "Assign defects to people" in the site's settings: off, a new defect
    /// does not ask who fixes it; on, it does, and the row says who.
    func testTheSiteSwitchShowsWhoFixesIt() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        XCTAssertTrue(app.tapSiteRow("site-defects"))
        XCTAssertTrue(app.screen("screen-defects").waitForExistence(timeout: 5))
        startDefect(app)
        XCTAssertTrue(app.buttons["defect-noted-by-0"].waitForExistence(timeout: 5), "who noted it is always asked")
        XCTAssertFalse(app.buttons["defect-fixer-0"].exists, "who fixes it is off by default")
        app.buttons["defect-cancel"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))
        XCTAssertTrue(app.openSiteSettings())
        let toggle = app.switches["defects-assign-switch"].firstMatch
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.exists, "site settings should have Assign defects to people")
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(flip(toggle))
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["site-editor-save"].tap()

        XCTAssertTrue(app.tapSiteRow("site-defects"))
        XCTAssertTrue(app.screen("screen-defects").waitForExistence(timeout: 5))
        startDefect(app)
        let ivan = app.buttons["defect-fixer-1"]
        XCTAssertTrue(ivan.waitForExistence(timeout: 5), "who fixes it is asked now")
        XCTAssertTrue(app.buttons["defect-fixer-0"].exists, "Me")
        XCTAssertTrue(app.tapAboveBottomBar(ivan, bar: app.buttons["defect-add"]))
        typeWhat("Cover missing", app)
        app.buttons["defect-add"].tap()
        let row = app.buttons["defects-row-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Ivan"), "the row says who fixes it: \(row.label)")
    }
}
