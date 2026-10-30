import XCTest

/// The site screen: its month, the usual day in one tap, the crew's day,
/// a changed time standing out, and a closed month refusing edits.
///
/// Every test starts from the seeded site (`SampleData.seedSite`):
/// "Kaiserstrasse 12" with Ivan and Marko on the crew, and yesterday written
/// up from 07:00 to 15:30 with a 30-minute break, Ivan leaving at 12:00.
/// Today is left empty. Run unpaid: the first site is free.
final class SiteDayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTickCrewAndSave() {
        let app = launch()
        openSite(app)

        // Today opens as not written, with yesterday on offer.
        XCTAssertTrue(app.screen("site-day-not-written").waitForExistence(timeout: 5), "today should say it is not written")
        XCTAssertTrue(app.buttons["site-day-same-as-usual"].waitForExistence(timeout: 5), "an empty day should offer Same as usual")
        let same = app.buttons["site-day-same-as-last"]
        XCTAssertTrue(same.waitForExistence(timeout: 5), "an empty day should offer Same as last day")
        // It names the day it copies from, which is yesterday, not today.
        XCTAssertTrue(
            same.label.contains(Self.mediumDate(daysFromToday: -1)),
            "Same as last day should name yesterday, \(Self.mediumDate(daysFromToday: -1)): \(same.label)"
        )
        same.tap()

        // Everyone who was there yesterday, at the site's times: Ivan's early
        // finish was a fact about yesterday and does not come with him.
        openCrewDay(app)
        wait(for: app.buttons["site-usual-you"], selected: true)
        wait(for: app.buttons["site-usual-Ivan"], selected: true)
        wait(for: app.buttons["site-usual-Marko"], selected: true)
        wait(for: app.buttons["site-late-Ivan"], selected: false)

        // Marko was somewhere else today, with no reason given.
        app.buttons["site-away-Marko"].tap()
        let none = app.buttons.matching(identifier: "site-absence-reason-none").firstMatch
        XCTAssertTrue(none.waitForExistence(timeout: 5), "Away should ask why")
        none.tap()
        wait(for: app.buttons["site-usual-Marko"], selected: false)
        wait(for: app.buttons["site-away-Marko"], selected: false)
        app.buttons["site-different-save"].tap()

        // Two people, eight hours each.
        let total = app.descendants(matching: .any)["site-crew-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("16"), "the crew total should be 16 hours: \(total.label)")

        // Saved: leave the site and come back.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "could not get back to the list")
        app.buttons["site-card"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site did not open again")
        openCrewDay(app)
        wait(for: app.buttons["site-usual-you"], selected: true)
        wait(for: app.buttons["site-usual-Ivan"], selected: true)
        wait(for: app.buttons["site-usual-Marko"], selected: false)
    }

    /// Same as usual writes the day in one tap: the site's usual day for
    /// the whole crew.
    func testSameAsUsualWritesTheDay() {
        let app = launch()
        openSite(app)

        let usual = app.buttons["site-day-same-as-usual"]
        XCTAssertTrue(usual.waitForExistence(timeout: 5), "an empty day should offer Same as usual")
        usual.tap()
        XCTAssertTrue(app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5), "the day should be written")
        XCTAssertFalse(app.screen("site-day-not-written").exists, "a written day must not say it is not written")
        XCTAssertTrue(app.descendants(matching: .any)["site-line-Marko"].exists, "the written day lists the crew")
    }

    func testLeftEarlyIsHighlighted() {
        let app = launch()
        openSite(app)

        select(app, daysFromToday: -1)

        let ivanLine = app.descendants(matching: .any)["site-line-Ivan"]
        XCTAssertTrue(ivanLine.waitForExistence(timeout: 5))
        let ownEnd = NSPredicate(format: "value CONTAINS %@", "12:00")
        expectation(for: ownEnd, evaluatedWith: ivanLine)
        waitForExpectations(timeout: 5)

        // Only Ivan: Marko and you kept the site's times.
        openCrewDay(app)
        wait(for: app.buttons["site-late-Ivan"], selected: true)
        wait(for: app.buttons["site-late-Marko"], selected: false)
        wait(for: app.buttons["site-late-you"], selected: false)
        app.buttons["site-different-cancel"].tap()
    }

    func testLockedMonthShowsRefusal() {
        let app = launch(arguments: ["-hours-closed-month"])
        openSite(app)

        // The day says why it cannot be changed, in the calendar's words.
        XCTAssertTrue(app.screen("site-day-locked").waitForExistence(timeout: 5), "a closed month must say so")
        XCTAssertTrue(app.staticTexts["This month is closed"].exists || app.screen("site-day-locked").label.contains("This month is closed"))

        // And nothing can be written or copied into it.
        let usual = app.buttons["site-day-same-as-usual"]
        XCTAssertTrue(usual.waitForExistence(timeout: 5))
        XCTAssertFalse(usual.isEnabled, "Same as usual must be off in a closed month")
        XCTAssertFalse(app.buttons["site-day-something-different"].isEnabled, "the crew's day must be off in a closed month")
        let same = app.buttons["site-day-same-as-last"]
        if same.exists {
            XCTAssertFalse(same.isEnabled, "Same as last day must be off in a closed month")
        }
    }

    /// Tapping a day in the site's month shows that day on the card, and
    /// tapping back shows today again — with nobody ticked when it is
    /// started from empty.
    func testTappingADayInTheMonthShowsIt() {
        let app = launch()
        openSite(app)

        let yesterday = select(app, daysFromToday: -1)
        wait(for: yesterday, selected: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5),
            "yesterday is written, so its card should show the crew's total"
        )
        XCTAssertTrue(app.descendants(matching: .any)["site-line-Ivan"].exists)
        XCTAssertFalse(app.screen("site-day-not-written").exists, "a written day must not say it is not written")

        let today = select(app, daysFromToday: 0)
        wait(for: today, selected: true)
        wait(for: yesterday, selected: false)
        XCTAssertTrue(app.screen("site-day-not-written").waitForExistence(timeout: 5), "today is not written")

        let empty = app.buttons["site-day-start-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an empty day should offer Start from empty")
        empty.tap()
        XCTAssertTrue(app.screen("site-different").waitForExistence(timeout: 5), "Start from empty opens the crew's day")
        wait(for: app.buttons["site-usual-you"], selected: false)
        wait(for: app.buttons["site-usual-Ivan"], selected: false)
        app.buttons["site-different-cancel"].tap()
        XCTAssertTrue(app.screen("site-day-not-written").waitForExistence(timeout: 5), "cancelling writes nothing")
    }

    // MARK: - Why someone was not here

    /// Ivan off sick: Away on his row gives him a reason, his row says so,
    /// it is still there after leaving the site, and Usual clears it. Read
    /// by identifier and by the selected trait, never by the translated
    /// words.
    func testMarkSomeoneSickAndTickingClearsIt() {
        let app = launch()
        openSite(app)

        let empty = app.buttons["site-day-start-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an empty day should offer Start from empty")
        empty.tap()

        let away = app.buttons["site-away-Ivan"]
        wait(for: away, selected: false)
        away.tap()
        let sick = app.buttons.matching(identifier: "site-absence-reason-sick").firstMatch
        XCTAssertTrue(sick.waitForExistence(timeout: 5), "the reasons should include Sick")
        sick.tap()
        wait(for: away, selected: true)
        app.buttons["site-different-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["site-line-Ivan"].waitForExistence(timeout: 5), "a reason is kept on the day")

        // Kept: leave the site and come back.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "could not get back to the list")
        app.buttons["site-card"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site did not open again")
        openCrewDay(app)
        wait(for: app.buttons["site-away-Ivan"], selected: true)

        // Usual clears it: he is here, and not away.
        app.buttons["site-usual-Ivan"].tap()
        wait(for: app.buttons["site-usual-Ivan"], selected: true)
        wait(for: app.buttons["site-away-Ivan"], selected: false)
        app.buttons["site-different-cancel"].tap()
    }

    /// Marko worked on another site: "On another site…" opens the sites and
    /// "Another site" for one not in the app; Usual clears it.
    func testChoosingOnAnotherSite() {
        let app = launch()
        openSite(app)

        let empty = app.buttons["site-day-start-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an empty day should offer Start from empty")
        empty.tap()

        let away = app.buttons["site-away-Marko"]
        wait(for: away, selected: false)
        away.tap()
        let otherSite = app.buttons.matching(identifier: "site-absence-reason-other-site").firstMatch
        XCTAssertTrue(otherSite.waitForExistence(timeout: 5), "the reasons should include On another site")
        otherSite.tap()
        let any = app.buttons.matching(identifier: "site-absence-other-site-any").firstMatch
        XCTAssertTrue(any.waitForExistence(timeout: 5), "On another site should offer Another site")
        any.tap()
        wait(for: away, selected: true)
        wait(for: app.buttons["site-usual-Marko"], selected: false)

        app.buttons["site-usual-Marko"].tap()
        wait(for: app.buttons["site-usual-Marko"], selected: true)
        wait(for: away, selected: false)
        app.buttons["site-different-cancel"].tap()
    }

    // MARK: - Diary and bad weather

    /// The day's diary keeps what was saved, and the day is marked in the month.
    func testDiaryKeepsWhatWasWritten() {
        let app = launch()
        openSite(app)

        let link = app.buttons["site-day-diary"]
        for _ in 0..<4 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the day should offer its diary")
        link.tap()
        let work = app.descendants(matching: .any)["site-diary-work"]
        XCTAssertTrue(work.waitForExistence(timeout: 5), "the diary should open")
        work.tap()
        work.typeText("Formwork")
        app.buttons["site-diary-save"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 5), "could not get back to the list")
        app.buttons["site-card"].firstMatch.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site did not open again")
        let again = app.buttons["site-day-diary"]
        for _ in 0..<4 where !again.isHittable { app.swipeUp() }
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        let field = app.descendants(matching: .any)["site-diary-work"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Formwork", "the diary should keep what was saved")
        app.buttons["site-diary-cancel"].tap()
    }

    /// Rained off on a written day: the stop shows, and can be taken back.
    func testRainedOffCanBeMarkedAndUndone() {
        let app = launch()
        openSite(app)
        select(app, daysFromToday: -1)

        let link = app.buttons["site-weather-menu"]
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5), "a written day should offer Bad weather")
        link.tap()
        let all = app.buttons["site-weather-stop-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        app.buttons["site-weather-stop-save"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["site-weather-stopped"].waitForExistence(timeout: 5),
                      "the day should say it was rained off")
        let lift = app.buttons["site-weather-lift"]
        XCTAssertTrue(lift.waitForExistence(timeout: 5))
        lift.tap()
        XCTAssertTrue(app.buttons["site-weather-menu"].waitForExistence(timeout: 5), "undo should bring Bad weather back")
    }

    // MARK: - Helpers

    /// Taps a day's cell in the site's grid and returns it. The grid opens on
    /// the selected day's week, so a day outside it — yesterday on the first
    /// day of a week, say — is not there at all, and the arrows move to it
    /// first: a week at a time while folded, a month while open.
    @discardableResult
    private func select(_ app: XCUIApplication, daysFromToday offset: Int) -> XCUIElement {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let key = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        let cell = app.buttons["site-day-\(key)"]
        if !cell.waitForExistence(timeout: 3) {
            // The tests only ever step back from today and return to it, so
            // the direction follows from the offset.
            let week = app.buttons[offset < 0 ? "site-week-previous" : "site-week-next"]
            let month = app.buttons[offset < 0 ? "site-month-previous" : "site-month-next"]
            (week.exists ? week : month).tap()
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "the site's month has no cell for \(key)")
        cell.tap()
        return cell
    }

    /// Part of the crew moves to the second site in the middle of the day
    /// (1.2): the banner says so, the mover's row names the other site, and
    /// Undo takes it back. Today is filled from yesterday first.
    func testMovingToAnotherSiteAndUndo() {
        let app = launch(arguments: ["-hours-second-site"])
        openSite(app)

        let same = app.buttons["site-day-same-as-last"]
        XCTAssertTrue(same.waitForExistence(timeout: 5))
        same.tap()
        XCTAssertTrue(app.descendants(matching: .any)["site-crew-total"].waitForExistence(timeout: 5))

        let move = app.buttons["site-day-move"].firstMatch
        for _ in 0..<3 where !move.isHittable { app.swipeUp() }
        XCTAssertTrue(move.waitForExistence(timeout: 5), "a written day with another site offers the move")
        move.tap()

        XCTAssertTrue(app.screen("site-move-sheet").waitForExistence(timeout: 5), "the move sheet did not open")
        let confirm = app.buttons["site-move-confirm"].firstMatch
        let destination = app.buttons["site-move-to-0"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        // Everyone ticked goes unless unticked: Marko stays.
        let marko = app.buttons["site-move-person-Marko"].firstMatch
        XCTAssertTrue(marko.waitForExistence(timeout: 5))
        marko.tap()
        XCTAssertTrue(confirm.isEnabled, "Move should be offered for a site and a time inside the day")
        confirm.tap()

        let banner = app.descendants(matching: .any)["site-move-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "the day should say who went where")
        XCTAssertTrue(banner.label.contains("Trg Pravde"), "the banner should name the other site: \(banner.label)")
        let ivan = app.descendants(matching: .any)["site-line-Ivan"]
        let movedValue = NSPredicate(format: "value CONTAINS %@", "Trg Pravde")
        expectation(for: movedValue, evaluatedWith: ivan)
        waitForExpectations(timeout: 5)
        XCTAssertFalse((app.descendants(matching: .any)["site-line-Marko"].value as? String ?? "").contains("Trg Pravde"), "Marko stayed")

        let undo = app.buttons["site-move-undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)], timeout: 5)
                == .completed,
            "Undo should take the move back"
        )
        XCTAssertFalse((ivan.value as? String ?? "").contains("Trg Pravde"), "Ivan is back on this site's times")
    }

    /// A date as the app's day headings write it ("Tue 19 Oct" in English),
    /// in the simulator's own locale, which is the one the app runs in.
    private static func mediumDate(daysFromToday offset: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }

    /// "Change" on a written day: the crew's day.
    private func openCrewDay(_ app: XCUIApplication) {
        let change = app.buttons["site-day-change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5), "a written day should offer Change")
        for _ in 0..<3 where !change.isHittable { app.swipeUp() }
        change.tap()
        XCTAssertTrue(app.screen("site-different").waitForExistence(timeout: 5), "the crew's day did not open")
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"] + arguments
        app.launch()
        return app
    }

    private func openSite(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.sites).waitForExistence(timeout: 10))
        app.tab(.sites).tap()
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the seeded site has no card")
        card.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 5), "the site day did not open")
    }

    /// Ticks are read from the selected trait rather than a label, which is
    /// translated.
    private func wait(for element: XCUIElement, selected: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is missing", file: file, line: line)
        let predicate = NSPredicate(format: "isSelected == %@", NSNumber(value: selected))
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element.identifier) should be \(selected ? "ticked" : "unticked")", file: file, line: line)
    }
}
