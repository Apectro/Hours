import XCTest

/// Settings › Connect to company, against the in-memory company the app
/// talks to with `-hours-connect-stub`: pair by the typed code, write a day
/// on the company's site, see it waiting, sync, and disconnect; and, with
/// `-hours-connect-office-day`, find the day the office wrote on the site.
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

    /// The office wrote today's day on the company's site: after pairing
    /// it is on the site, written, and says who wrote it; nothing of it is
    /// sent back.
    func testADayTheOfficeWroteIsOnTheSite() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-connect-stub", "-hours-connect-office-day"]
        app.launch()
        openConnect(app)

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
        XCTAssertTrue(app.screen("connect-state-connected").waitForExistence(timeout: 10), "Settings should show Connected")
        XCTAssertTrue(app.screen("connect-up-to-date").waitForExistence(timeout: 5), "the office's own day is not sent back to it")

        // The company's site, and today on it: written, by the office.
        app.tab(.sites).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5))
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the company's site should be on the Sites tab")
        card.tap()
        let today = app.buttons.matching(identifier: "site-overview-day-\(XCUIApplication.todayKey)").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the site's month has no today")
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5), "the office's day should be written on the site")
        XCTAssertTrue(app.screen("connect-line-office").waitForExistence(timeout: 5), "the day should say the office wrote it")
        XCTAssertFalse(app.buttons.matching(identifier: "site-day-same-as-usual").firstMatch.exists, "a written day offers no Save")
        XCTAssertFalse(app.buttons.matching(identifier: "connect-office-keep-mine").firstMatch.exists, "nothing of the phone's own to choose")

        // Still nothing waiting.
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-connect").waitForExistence(timeout: 5), "the Settings tab should still be on Connect")
        XCTAssertTrue(app.screen("connect-up-to-date").waitForExistence(timeout: 10), "looking at the office's day queues nothing")
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
