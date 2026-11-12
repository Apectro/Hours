import XCTest

/// Settings › Connect to company, against the in-memory company the app
/// talks to with `-hours-connect-stub`: pair by the typed code, write a day
/// on the company's site, see it waiting, sync, and disconnect.
///
/// Everything by identifier; the stub's site and people are its own and
/// nothing here reaches the network.
final class ConnectUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testPairWriteADaySyncAndDisconnect() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-connect-stub"]
        app.launch()

        openConnect(app)

        // Not connected: the typed address and code, then which firm.
        let address = app.textFields.matching(identifier: "connect-address").firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5), "the Connect screen has no address field")
        address.tap()
        address.typeText("firm.example/api/zeitkonto")
        let code = app.textFields.matching(identifier: "connect-code").firstMatch
        code.tap()
        code.typeText("k7qf-3mzp\n")
        let pair = app.buttons.matching(identifier: "connect-pair").firstMatch
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        pair.tap()
        let confirm = app.buttons.matching(identifier: "connect-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "connecting should ask which firm first")
        confirm.tap()

        // Connected, and nothing waiting: the company's site came in, and
        // nothing of the office's is sent back to it.
        XCTAssertTrue(app.screen("connect-state-connected").waitForExistence(timeout: 10), "Settings should show Connected")
        XCTAssertTrue(app.screen("connect-up-to-date").waitForExistence(timeout: 5), "a fresh connection has nothing waiting")

        // A day on the company's site.
        app.tab(.sites).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5))
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the company's site should be on the Sites tab")
        card.tap()
        XCTAssertTrue(app.screen("site-from-company").waitForExistence(timeout: 5), "the site should say it is from the company")
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5))
        let usual = app.buttons.matching(identifier: "site-day-same-as-usual").firstMatch
        XCTAssertTrue(usual.waitForExistence(timeout: 5), "the web's usual day should be offered")
        usual.tap()
        XCTAssertTrue(app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5), "the day should be written")

        // One waiting; Sync now sends it.
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-connect").waitForExistence(timeout: 5), "the Settings tab should still be on Connect")
        let waiting = app.screen("connect-waiting")
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "the day should be waiting to send")
        XCTAssertEqual(waiting.value as? String, "1")
        let sync = app.buttons.matching(identifier: "connect-sync-now").firstMatch
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        sync.tap()
        XCTAssertTrue(app.screen("connect-up-to-date").waitForExistence(timeout: 10), "after Sync now everything is sent")

        // Disconnect, confirmed: back to the pairing screen.
        let disconnect = app.buttons.matching(identifier: "connect-disconnect").firstMatch
        XCTAssertTrue(app.scrollTo(disconnect), "Connect has no Disconnect")
        disconnect.tap()
        let sure = app.buttons.matching(identifier: "connect-disconnect-confirm").firstMatch
        XCTAssertTrue(sure.waitForExistence(timeout: 5), "Disconnect should ask first")
        sure.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "connect-pair").firstMatch.waitForExistence(timeout: 5), "disconnected, the screen offers pairing again")
        XCTAssertFalse(app.screen("connect-state-connected").exists)
    }

    func testAWrongCodeSaysSo() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-connect-stub"]
        app.launch()
        openConnect(app)

        let address = app.textFields.matching(identifier: "connect-address").firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("firm.example/api/zeitkonto")
        let code = app.textFields.matching(identifier: "connect-code").firstMatch
        code.tap()
        code.typeText("AAAABBBB\n")
        app.buttons.matching(identifier: "connect-pair").firstMatch.tap()
        let confirm = app.buttons.matching(identifier: "connect-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.screen("connect-problem").waitForExistence(timeout: 10), "a wrong code should say what to do")
        XCTAssertFalse(app.screen("connect-state-connected").exists)
    }

    private func openConnect(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10), file: file, line: line)
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 5), file: file, line: line)
        let row = app.buttons.matching(identifier: "settings-connect").firstMatch
        XCTAssertTrue(app.scrollTo(row), "Settings has no Connect to company", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.screen("screen-connect").waitForExistence(timeout: 5), "Connect to company did not open", file: file, line: line)
    }
}
