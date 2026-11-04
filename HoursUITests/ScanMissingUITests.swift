import XCTest

/// Scanning material and the site's Missing list (1.3), on the seeded site.
/// The simulator has no camera scanner, so the scanner offers its typed-code
/// field — the same path every real scan takes after the camera reads it.
final class ScanMissingUITests: XCTestCase {
    private let code = "4015081677891"

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

    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    // MARK: - Scanning in the extra-work editor

    /// A new code is named once and added; the same code again counts the
    /// line up to 2 without asking again.
    func testAScannedCodeIsNamedOnceAndCountsUp() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let add = app.buttons["extra-work-add"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the day should offer Add extra work")
        add.tap()
        XCTAssertTrue(app.screen("screen-extra-work-editor").waitForExistence(timeout: 5), "the editor did not open")

        let scan = app.buttons["extra-work-scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "Material should offer Scan")
        scan.tap()
        XCTAssertTrue(app.screen("screen-scanner").waitForExistence(timeout: 5), "the scanner did not open")

        // No camera here: the code is typed.
        let field = app.textFields["scanner-code-field"]
        type(code, into: field)
        app.buttons["scanner-code-add"].tap()

        // Seen for the first time: named once.
        let name = app.textFields["new-item-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "a new code should ask for a name")
        XCTAssertTrue(app.descendants(matching: .any)["new-item-code"].exists, "the New item sheet shows the code")
        name.tap()
        name.typeText("Junction box IP65")
        app.buttons["new-item-save"].tap()

        let last = app.descendants(matching: .any)["scanner-last-amount"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "the card should say what was added")
        XCTAssertTrue(app.descendants(matching: .any)["scanner-line-0"].exists, "the session lists the item")

        // The same code again: known now, no question, one more.
        type(code, into: field)
        app.buttons["scanner-code-add"].tap()
        XCTAssertFalse(app.textFields["new-item-name"].waitForExistence(timeout: 2), "a named code is not asked for again")
        XCTAssertFalse(app.descendants(matching: .any)["scanner-line-1"].exists, "still one item in the session")

        app.buttons["scanner-done"].tap()
        let quantity = app.buttons["extra-work-quantity-0"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5), "the scanned item should be a line on the job")
        XCTAssertTrue((quantity.value as? String)?.hasPrefix("2") == true, "two scans are two: \(String(describing: quantity.value))")
        XCTAssertFalse(app.buttons["extra-work-quantity-1"].exists, "one line, not two")
        app.buttons["extra-work-cancel"].tap()
    }

    // MARK: - Reading the name off the box

    /// A new code offers the names the camera read around it (here handed
    /// in by `-hours-box-text`, cleaned: no code, no price); a tap fills the
    /// name, which stays editable.
    func testANewCodeOffersNamesFromTheBox() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-box-text", "Junction box IP65|\(code)|4,99 €|Abzweigdose grau"]
        app.launch()
        openSite(app)
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let add = app.buttons["extra-work-add"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the day should offer Add extra work")
        add.tap()
        XCTAssertTrue(app.screen("screen-extra-work-editor").waitForExistence(timeout: 5), "the editor did not open")
        app.buttons["extra-work-scan"].tap()
        XCTAssertTrue(app.screen("screen-scanner").waitForExistence(timeout: 5), "the scanner did not open")
        type(code, into: app.textFields["scanner-code-field"])
        app.buttons["scanner-code-add"].tap()

        let name = app.textFields["new-item-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "a new code should ask for a name")
        let first = app.buttons["new-item-suggestion-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the names read off the box should be offered")
        XCTAssertEqual(first.label, "Junction box IP65")
        XCTAssertEqual(app.buttons["new-item-suggestion-1"].label, "Abzweigdose grau")
        XCTAssertFalse(app.buttons["new-item-suggestion-2"].exists, "the code and the price are not names")

        app.buttons["new-item-suggestion-1"].tap()
        XCTAssertEqual(name.value as? String, "Abzweigdose grau", "a tap fills the name")
        name.tap()
        name.typeText(" 5x")
        XCTAssertEqual(name.value as? String, "Abzweigdose grau 5x", "the name stays editable")
        app.buttons["new-item-save"].tap()

        let last = app.descendants(matching: .any)["scanner-last-amount"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "the named item is added")
        app.buttons["scanner-done"].tap()
        app.buttons["extra-work-cancel"].tap()
    }

    /// Scan text beside Missing's search: lines added to the tray (typed
    /// here, as the simulator has no camera) are joined with a space, Clear
    /// empties it, and Use fills the field.
    func testScanTextFillsTheMissingAddField() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        XCTAssertTrue(app.tapSiteRow("site-missing"), "the site's page should have a Missing row")
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "Missing did not open")
        app.buttons["missing-add"].tap()
        XCTAssertTrue(app.screen("screen-missing-add").waitForExistence(timeout: 5), "the add sheet did not open")

        let scanText = app.buttons["missing-add-scan-text"]
        XCTAssertTrue(scanText.waitForExistence(timeout: 5), "the search field should offer Scan text")
        scanText.tap()
        XCTAssertTrue(app.screen("screen-text-scan").waitForExistence(timeout: 5), "Scan text did not open")
        XCTAssertFalse(app.buttons["text-scan-use"].isEnabled, "nothing to use yet")

        let field = app.textFields["text-scan-field"]
        type("Old line", into: field)
        app.buttons["text-scan-add"].tap()
        app.buttons["text-scan-clear"].tap()
        type("Junction box", into: field)
        app.buttons["text-scan-add"].tap()
        type("IP65", into: field)
        app.buttons["text-scan-add"].tap()
        let tray = app.descendants(matching: .any)["text-scan-tray"]
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        XCTAssertEqual(tray.label, "Junction box IP65", "lines are joined with a space; Clear emptied the first")
        app.buttons["text-scan-use"].tap()

        let search = app.textFields["missing-add-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Junction box IP65", "Use fills the field")
        XCTAssertTrue(app.buttons["missing-add-new"].waitForExistence(timeout: 5), "the text read is offered as a new item")
        app.buttons["missing-add-cancel"].tap()
    }

    /// Scan text beside What was done adds the text after what is typed,
    /// with a space, instead of replacing it.
    func testScanTextIsAddedAfterWhatWasDone() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let add = app.buttons["extra-work-add"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the day should offer Add extra work")
        add.tap()
        XCTAssertTrue(app.screen("screen-extra-work-editor").waitForExistence(timeout: 5), "the editor did not open")

        let description = app.descendants(matching: .any)["extra-work-description"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Fitted")

        app.buttons["extra-work-description-scan-text"].tap()
        XCTAssertTrue(app.screen("screen-text-scan").waitForExistence(timeout: 5), "Scan text did not open")
        type("LED panel", into: app.textFields["text-scan-field"])
        app.buttons["text-scan-add"].tap()
        app.buttons["text-scan-use"].tap()
        // Wait for the sheet to close before looking at the field.
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.screen("screen-text-scan"))
        wait(for: [closed], timeout: 5)

        XCTAssertEqual(description.value as? String, "Fitted LED panel", "Use adds after what was typed")
        app.buttons["extra-work-cancel"].tap()
    }

    // MARK: - Missing

    /// Added by a new name, the same item found by search counts it up,
    /// a second item added; Send the list says what is needed; a swipe
    /// orders one.
    func testTheMissingListAddsSendsAndOrders() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)

        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tapSiteRow("site-missing"), "the site's page should have a Missing row")
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "Missing did not open")

        // A new item, by name.
        addMissing(app) {
            self.type("Junction box IP65", into: app.textFields["missing-add-search"])
            let new = app.buttons["missing-add-new"]
            XCTAssertTrue(new.waitForExistence(timeout: 5), "typed text should offer Add as a new item")
            new.tap()
            let plus = app.buttons["missing-add-new-plus"]
            XCTAssertTrue(plus.waitForExistence(timeout: 5), "the row should have its own +")
            plus.tap()
            plus.tap()
            self.type("2nd floor corridor", into: app.textFields["missing-add-note"])
        }
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-0"].waitForExistence(timeout: 5), "the item should be listed")

        // The same item again, found by search: counted up, not listed twice.
        addMissing(app) {
            self.type("junc", into: app.textFields["missing-add-search"])
            let match = app.buttons["missing-add-match-0"]
            XCTAssertTrue(match.waitForExistence(timeout: 5), "the search should find the item")
            match.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["missing-row-1"].exists, "the same needed item is counted up")

        // A second item.
        addMissing(app) {
            self.type("Cable NYM 3x1.5", into: app.textFields["missing-add-search"])
            app.buttons["missing-add-new"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-1"].waitForExistence(timeout: 5), "a second item should be listed")

        // Send the list: the message names what is needed, with how many.
        let send = app.buttons["missing-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "the list should offer Send the list")
        send.tap()
        let text = app.descendants(matching: .any)["missing-send-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Send the list should show the message")
        XCTAssertTrue(text.label.contains("4 × Junction box IP65"), "the message: \(text.label)")
        XCTAssertTrue(text.label.contains("Cable NYM 3x1.5"), "the message: \(text.label)")
        XCTAssertTrue(app.switches["missing-send-mark"].exists, "Mark them as ordered is offered")
        XCTAssertTrue(app.buttons["missing-send-message"].exists)
        XCTAssertTrue(app.buttons["missing-send-pdf"].exists)
        app.buttons["missing-send-close"].tap()

        // A swipe orders the first; it leaves Needed and is under Ordered.
        let first = app.descendants(matching: .any)["missing-row-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.swipeLeft()
        let ordered = app.buttons["missing-mark-ordered"]
        XCTAssertTrue(ordered.waitForExistence(timeout: 5), "a swipe should offer Ordered")
        ordered.tap()
        XCTAssertFalse(app.descendants(matching: .any)["missing-row-1"].waitForExistence(timeout: 2), "one left needed")
        let states = app.segmentedControls["missing-state"]
        XCTAssertTrue(states.waitForExistence(timeout: 5))
        states.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-0"].waitForExistence(timeout: 5), "the ordered item is under Ordered")
    }

    /// Two items with their quantities in one go: each row has its own − / +,
    /// the first stays on top when the search changes, and one Add puts both
    /// on the list with their counts.
    func testSeveralItemsAreAddedInOneGo() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        XCTAssertTrue(app.tapSiteRow("site-missing"), "the site's page should have a Missing row")
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "Missing did not open")
        app.buttons["missing-add"].tap()
        XCTAssertTrue(app.screen("screen-missing-add").waitForExistence(timeout: 5), "the add sheet did not open")
        let save = app.buttons["missing-add-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "nothing chosen yet")

        // The first: + from nothing is one, + again is two; − takes one back.
        let search = app.textFields["missing-add-search"]
        type("Junction box IP65", into: search)
        let firstPlus = app.buttons["missing-add-new-plus"]
        XCTAssertTrue(firstPlus.waitForExistence(timeout: 5), "the typed row should have its own +")
        XCTAssertFalse(app.buttons["missing-add-new-minus"].exists, "at nothing the row shows only +")
        firstPlus.tap()
        firstPlus.tap()
        firstPlus.tap()
        let firstMinus = app.buttons["missing-add-new-minus"]
        XCTAssertTrue(firstMinus.waitForExistence(timeout: 5), "a chosen row has −")
        firstMinus.tap()
        XCTAssertTrue(
            (app.buttons["missing-add-new-quantity"].value as? String)?.hasPrefix("2") == true,
            "two of the first: \(String(describing: app.buttons["missing-add-new-quantity"].value))"
        )
        XCTAssertTrue(save.isEnabled, "one item chosen")

        // A new search: the first stays chosen, on top.
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Junction box IP65".count))
        search.typeText("Cable grey")
        let kept = app.buttons["missing-add-match-0-quantity"]
        XCTAssertTrue(kept.waitForExistence(timeout: 5), "the first item stays on top, chosen")
        XCTAssertTrue((kept.value as? String)?.hasPrefix("2") == true, "still two: \(String(describing: kept.value))")

        // The second: a tap on the row is one, then two more.
        let second = app.buttons["missing-add-new"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        let secondPlus = app.buttons["missing-add-new-plus"]
        secondPlus.tap()
        secondPlus.tap()
        XCTAssertTrue(
            (app.buttons["missing-add-new-quantity"].value as? String)?.hasPrefix("3") == true,
            "three of the second: \(String(describing: app.buttons["missing-add-new-quantity"].value))"
        )

        save.tap()
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "back on the list")
        let rows = [app.descendants(matching: .any)["missing-row-0"], app.descendants(matching: .any)["missing-row-1"]]
        XCTAssertTrue(rows[0].waitForExistence(timeout: 5), "the first item should be listed")
        XCTAssertTrue(rows[1].exists, "the second item should be listed")
        XCTAssertFalse(app.descendants(matching: .any)["missing-row-2"].exists, "two items, two rows")

        // The counts: the message names both, with how many.
        app.buttons["missing-send"].tap()
        let text = app.descendants(matching: .any)["missing-send-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Send the list should show the message")
        XCTAssertTrue(text.label.contains("2 × Junction box IP65"), "the message: \(text.label)")
        XCTAssertTrue(text.label.contains("3 × Cable grey"), "the message: \(text.label)")
        app.buttons["missing-send-close"].tap()
    }

    /// The crew's day opens the add sheet for its site.
    func testTheCrewsDayNotesSomethingMissing() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openSite(app)
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")

        let link = app.buttons["site-day-missing"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the day should offer Something's missing")
        link.tap()
        XCTAssertTrue(app.screen("screen-missing-add").waitForExistence(timeout: 5), "the add sheet did not open")
        type("Wago 221", into: app.textFields["missing-add-search"])
        app.buttons["missing-add-new"].tap()
        let plus = app.buttons["missing-add-new-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "the day's sheet has the same − / + on each row")
        plus.tap()
        app.buttons["missing-add-save"].tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "back on the day")

        // On the site's page it is one needed.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tapSiteRow("site-missing"), "the site's page should have a Missing row")
        XCTAssertTrue(app.descendants(matching: .any)["missing-row-0"].waitForExistence(timeout: 5), "the item noted on the day is on the list")
    }

    /// Opens the add sheet, does what is given, and adds.
    private func addMissing(_ app: XCUIApplication, _ fill: () -> Void) {
        let add = app.buttons["missing-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Missing should have + in its toolbar")
        add.tap()
        XCTAssertTrue(app.screen("screen-missing-add").waitForExistence(timeout: 5), "the add sheet did not open")
        fill()
        let save = app.buttons["missing-add-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "something is chosen")
        save.tap()
        XCTAssertTrue(app.screen("screen-missing").waitForExistence(timeout: 5), "back on the list")
    }
}
