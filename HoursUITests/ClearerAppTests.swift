import XCTest

/// The clearer app (1.2): the new-site wizard, the site's four buttons, and
/// the search in Settings. Everything by identifier; the few labels read are
/// numbers and the names the tests typed.
final class ClearerAppTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The wizard

    /// Copy from a site: its crew comes along, ticked, and the new site is
    /// made with its own name.
    func testWizardCopiesASiteAndCreatesIt() {
        // Pro, because a second active site is Pro while payments are on.
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "site-card").firstMatch.waitForExistence(timeout: 5), "the seeded site has no card")
        app.buttons.matching(identifier: "sites-add").firstMatch.tap()

        let copy = app.buttons["wizard-start-copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "the wizard offers no Copy from a site")
        copy.tap()
        app.wizardNext()

        let name = app.textFields["site-name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the wizard has no name field")
        name.tap()
        name.typeText("Trg Pravde")
        app.wizardNext()

        // Ivan and Marko came with the copy: three on the crew with you.
        let count = app.descendants(matching: .any)["wizard-crew-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "the crew step says nothing about the crew")
        XCTAssertTrue(count.label.contains("3"), "the copied crew should be ticked: \(count.label)")

        for _ in 0..<3 { app.wizardNext() }
        let crewLine = app.buttons["wizard-check-crew"].firstMatch
        XCTAssertTrue(crewLine.waitForExistence(timeout: 5), "the check has no Crew line")
        XCTAssertTrue(crewLine.label.contains("Ivan") && crewLine.label.contains("Marko"), "the check should name the crew: \(crewLine.label)")
        app.buttons["wizard-create"].firstMatch.tap()

        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5))
        let cards = app.buttons.matching(identifier: "site-card")
        XCTAssertTrue(cards.element(boundBy: 1).waitForExistence(timeout: 5), "the new site has no card")
        let labels = cards.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.contains("Trg Pravde") && $0.contains("Crew 3") }, "the new site should carry its name and crew: \(labels)")
    }

    /// Several sites at once: names one per line, one setup, all created.
    func testSeveralSitesAtOnceCreatesThemAll() {
        let app = XCUIApplication.hours(pro: true)
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        app.buttons.matching(identifier: "sites-add").firstMatch.tap()
        let several = app.buttons["wizard-start-several"].firstMatch
        XCTAssertTrue(several.waitForExistence(timeout: 5), "the wizard offers no Several sites at once")
        several.tap()
        app.wizardNext()

        let names = app.descendants(matching: .any).matching(identifier: "wizard-several-names").firstMatch
        XCTAssertTrue(names.waitForExistence(timeout: 5), "there is nowhere to type the names")
        names.tap()
        names.typeText("Solarka\nVukovarska 5\nsolarka\nTrg Pravde")
        let count = app.descendants(matching: .any)["wizard-several-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "the names step does not count the sites")
        XCTAssertTrue(count.label.contains("3"), "the repeated name should count once: \(count.label)")

        for _ in 0..<4 { app.wizardNext() }
        app.buttons["wizard-create"].firstMatch.tap()

        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5))
        let cards = app.buttons.matching(identifier: "site-card")
        XCTAssertTrue(cards.element(boundBy: 2).waitForExistence(timeout: 5), "three sites should have been made")
        XCTAssertFalse(cards.element(boundBy: 3).exists, "a name typed twice is one site")
    }

    // MARK: - A site's buttons

    func testTheSiteButtonsOpenCrewDiarySheetAndExtraWork() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()

        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons.matching(identifier: "site-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site did not open")

        // Crew, pushed.
        app.buttons["site-crew"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-crew").waitForExistence(timeout: 5), "Crew did not open the crew")
        XCTAssertTrue(app.buttons["site-sign-off"].firstMatch.exists, "the crew should offer the sign-off")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Diary, a sheet.
        let diary = app.buttons["site-diary-list"].firstMatch
        XCTAssertTrue(diary.waitForExistence(timeout: 5), "the site has no Diary button")
        diary.tap()
        XCTAssertTrue(app.buttons["site-diary-list-done"].firstMatch.waitForExistence(timeout: 5), "Diary did not open the diary")
        app.buttons["site-diary-list-done"].firstMatch.tap()

        // Sheet, the site's export.
        app.buttons["site-export"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "Sheet did not open the export")
        app.buttons["export-done"].firstMatch.tap()

        // Extra work, the report.
        app.buttons["site-extra-work-report"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 10), "Extra work did not open the report")
        app.buttons["extra-work-report-done"].firstMatch.tap()

        // And the gear, the site's settings, with its usual day.
        app.buttons["site-edit"].firstMatch.tap()
        XCTAssertTrue(app.switches["site-editor-usual-times"].firstMatch.waitForExistence(timeout: 5), "the site's settings have no usual day")
    }

    // MARK: - Settings

    func testSettingsSearchFindsOvertime() {
        let app = XCUIApplication.hours()
        app.launch()

        XCTAssertTrue(app.tab(.settings).waitForExistence(timeout: 10))
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 5))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Settings has no search field")
        search.tap()
        search.typeText("overtime")

        let row = app.buttons["settings-calculation"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "searching overtime should find Overtime & balance")
        XCTAssertFalse(app.buttons["settings-theme"].firstMatch.exists, "the search should leave out what does not match")

        // A word from a screen one level down: km finds Allowance & travel.
        search.buttons.firstMatch.tap()
        search.typeText("km")
        XCTAssertTrue(app.buttons["settings-allowance"].firstMatch.waitForExistence(timeout: 5), "searching km should find Allowance & travel")
    }
}
