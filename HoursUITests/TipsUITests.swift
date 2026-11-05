import XCTest

/// Tips at the top of a screen (2026-11-05), on the seeded site
/// (`-hours-sample-site`), which has a crew and a day written and no work
/// days set: the owner's case. Tips are off in a UI test run unless
/// `-hours-tips` asks for them.
final class TipsUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The seeded site's page, tips on. `keepsSettings` keeps the run's
    /// settings across a relaunch; `resetsSettings` starts them afresh.
    private func launchOnSite(keepsSettings: Bool = false, resetsSettings: Bool = false) -> XCUIApplication {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site", "-hours-tips"]
        if keepsSettings { app.launchArguments += ["-hours-keep-settings"] }
        if resetsSettings { app.launchArguments += ["-hours-reset-settings"] }
        app.launch()
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        XCTAssertTrue(tapUntil(card, shows: app.screen("screen-site").firstMatch), "the site did not open")
        return app
    }

    private func workDaysTip(_ app: XCUIApplication) -> XCUIElement {
        app.screen("tip-site-work-days").firstMatch
    }

    /// The site's Defects, from its page.
    private func openDefects(_ app: XCUIApplication) {
        let row = app.buttons.matching(identifier: "site-defects").firstMatch
        let bar = app.buttons.matching(identifier: "site-write-today").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the site has no Defects row")
        XCTAssertTrue(app.tapAboveBottomBar(row, bar: bar), "the Defects row could not be tapped")
        XCTAssertTrue(app.screen("screen-defects").firstMatch.waitForExistence(timeout: 5), "Defects did not open")
    }

    /// Settings › More › Tips.
    private func openTipsSettings(_ app: XCUIApplication) {
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.openSettingsMore(), "Settings › More did not open")
        let row = app.buttons.matching(identifier: "settings-tips").firstMatch
        XCTAssertTrue(app.scrollTo(row), "More has no Tips row")
        XCTAssertTrue(tapUntil(row, shows: app.screen("screen-settings-tips").firstMatch), "Tips did not open")
    }

    /// The owner's case: the tip shows, "Set work days" opens the site's
    /// work days, and once Mon–Fri are saved the tip is gone.
    func testTheWorkDaysTipGoesOnceTheWorkDaysAreSet() {
        let app = launchOnSite()
        let tip = workDaysTip(app)
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "the site shows no work-days tip")

        let action = app.buttons.matching(identifier: "tip-site-work-days-action").firstMatch
        let workDays = app.screen("screen-site-work-days").firstMatch
        XCTAssertTrue(tapUntil(action, shows: workDays), "Set work days did not open the work days")

        // Monday to Friday: weekdays 2 to 6.
        for weekday in 2...6 {
            let day = app.buttons.matching(identifier: "work-day-\(weekday)").firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 5), "no button for weekday \(weekday)")
            day.tap()
        }
        let save = app.buttons.matching(identifier: "site-work-days-save").firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "the work days have no Save")
        save.tap()
        XCTAssertTrue(waitUntilGone(workDays), "the site's settings did not close")

        XCTAssertTrue(app.screen("screen-site").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilGone(tip), "the work-days tip is still there with the work days set")
    }

    /// ✕ on Defects' "Photo first": gone, and still gone after a relaunch,
    /// while the site's own tip, never dismissed, is still there.
    func testADismissedTipStaysDismissedAfterARelaunch() {
        var app = launchOnSite(keepsSettings: true, resetsSettings: true)
        openDefects(app)
        let tip = app.screen("tip-defect-photos").firstMatch
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "empty Defects show no tip")
        let dismiss = app.buttons.matching(identifier: "tip-defect-photos-dismiss").firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        XCTAssertTrue(waitUntilGone(tip), "✕ did not hide the tip")

        app.terminate()
        app = launchOnSite(keepsSettings: true)
        XCTAssertTrue(workDaysTip(app).waitForExistence(timeout: 5), "the site's own tip went too")
        openDefects(app)
        XCTAssertFalse(
            app.screen("tip-defect-photos").firstMatch.waitForExistence(timeout: 2),
            "the dismissed tip came back after a relaunch"
        )
    }

    /// "Show all tips again" brings a dismissed tip back; Show tips off
    /// hides it.
    func testTheSettingsBringTipsBackAndSwitchThemOff() {
        let app = launchOnSite()
        let tip = workDaysTip(app)
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "the site shows no work-days tip")
        app.buttons.matching(identifier: "tip-site-work-days-dismiss").firstMatch.tap()
        XCTAssertTrue(waitUntilGone(tip), "✕ did not hide the tip")

        openTipsSettings(app)
        let reset = app.buttons.matching(identifier: "settings-tips-reset").firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        // The Sites tab is still on the site.
        app.tab(.sites).tap()
        XCTAssertTrue(tip.waitForExistence(timeout: 5), "Show all tips again did not bring the tip back")

        app.tab(.settings).tap()
        let show = app.switches.matching(identifier: "settings-tips-show").firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5), "Tips has no Show tips switch")
        XCTAssertTrue(flip(show), "Show tips did not switch off")

        app.tab(.sites).tap()
        XCTAssertTrue(app.screen("screen-site").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilGone(tip), "a tip still shows with tips switched off")
    }
}
