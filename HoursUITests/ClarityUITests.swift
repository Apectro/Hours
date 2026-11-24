import XCTest

/// Own hours and site hours told apart, and a day's earnings (2026-11-24):
/// the chips above the month and what they do to its totals, "Earned this
/// day" with its eye, the editor's note that sends site hours to the site,
/// and "Write today's hours". Everything by identifier; the labels read are
/// figures and the names the sample data typed.
final class ClarityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Yesterday, which the sample site has written (`SampleData.seedSite`):
    /// its key in the calendar, and whether it is in the month that opens.
    private static var yesterday: (key: Int, isThisMonth: Bool) {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let key = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return (key, calendar.isDate(day, equalTo: now, toGranularity: .month))
    }

    /// The Today tab on the month that holds yesterday's site day: on the
    /// 1st that is last month.
    private func openMonthWithTheSiteDay(_ app: XCUIApplication) {
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.tab(.calendar).tap()
        if !Self.yesterday.isThisMonth {
            let previous = app.buttons["calendar-previous"].firstMatch
            XCTAssertTrue(previous.waitForExistence(timeout: 5), "no ‹ beside the title")
            previous.tap()
        }
    }

    // MARK: - The month's chips

    func testFilterChipsShowWithASiteAndFilterTheSummary() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openMonthWithTheSiteDay(app)

        let all = app.buttons["calendar-filter-all"].firstMatch
        let site = app.buttons["calendar-filter-site-0"].firstMatch
        let own = app.buttons["calendar-filter-own"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 10), "with a site there should be chips above the month")
        XCTAssertTrue(site.exists, "the site with hours in the month should have a chip")
        XCTAssertTrue(site.label.contains("Kaiserstrasse"), "the chip should carry the site's name: \(site.label)")
        XCTAssertTrue(own.exists, "there should be a chip for your own hours")

        // All: the totals say where the hours came from.
        let worked = app.descendants(matching: .any)["calendar-summary-worked"].firstMatch
        let sources = app.descendants(matching: .any)["calendar-summary-sources"].firstMatch
        let filtered = app.descendants(matching: .any)["calendar-summary-filtered"].firstMatch
        scrollTo(worked, in: app)
        XCTAssertTrue(worked.exists, "the month's totals have no Worked figure")
        XCTAssertTrue(sources.exists, "under Worked there should be Sites … · Own …")
        XCTAssertFalse(filtered.exists, "All is the default: nothing is filtered yet")
        let whole = worked.label
        XCTAssertFalse(whole.isEmpty)
        XCTAssertTrue(sources.label.contains(whole), "every hour of the month is the site's: \(sources.label) / \(whole)")

        // Own: none of the month's hours are your own, so the figure changes.
        app.bringToScreen(own)
        own.tap()
        scrollTo(filtered, in: app)
        XCTAssertTrue(filtered.exists, "a chip should make the totals say they are filtered")
        XCTAssertNotEqual(worked.label, whole, "Own should show only your own hours, and there are none")

        // The site: all of them again, under its name.
        app.bringToScreen(site)
        site.tap()
        scrollTo(worked, in: app)
        XCTAssertEqual(worked.label, whole, "the site's chip should show the site's hours")
        XCTAssertTrue(sources.label.contains("Kaiserstrasse"), "the totals should name the source: \(sources.label)")

        // And back.
        app.bringToScreen(all)
        all.tap()
        scrollTo(worked, in: app)
        XCTAssertTrue(waitUntilGone(filtered), "All should bring the month's totals back")
        XCTAssertEqual(worked.label, whole)
    }

    func testWithoutASiteThereAreNoChipsAndNoWriteTodayButton() {
        let app = XCUIApplication.hours()
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.tab(.calendar).tap()
        XCTAssertTrue(app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch.waitForExistence(timeout: 10), "the month did not appear")

        XCTAssertFalse(app.buttons["calendar-filter-all"].firstMatch.exists, "no site: no chips")
        let today = app.buttons["today-card"].firstMatch
        app.bringToScreen(today)
        XCTAssertTrue(today.exists)
        XCTAssertFalse(app.buttons["today-write-hours"].firstMatch.exists, "no site: the Today tab stays as it was")
    }

    // MARK: - Earned this day

    func testTheDayShowsWhatItEarnedAndTheEyeHidesIt() {
        // The sample month sets a rate and writes today on its site.
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-data"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 20))
        app.tab(.calendar).tap()

        let today = app.buttons["day-\(XCUIApplication.todayKey)"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10), "today is not in the month")
        app.bringToScreen(today)
        today.tap()
        XCTAssertTrue(app.screen("screen-calendar-day").waitForExistence(timeout: 10), "the day's sheet did not open")
        XCTAssertTrue(
            app.descendants(matching: .any)["day-card-on-sites"].firstMatch.waitForExistence(timeout: 5),
            "a day written on a site should say On sites"
        )

        let total = app.descendants(matching: .any)["day-card-earned-total"].firstMatch
        scrollTo(total, in: app)
        XCTAssertTrue(total.exists, "with pay set, the day should say what it earned")
        XCTAssertTrue(app.descendants(matching: .any)["day-card-earned"].firstMatch.exists)
        let shown = total.label
        XCTAssertNotEqual(shown, "•••", "amounts are shown until hidden")

        // The eye hides every amount, and shows them again.
        let eye = app.buttons["day-card-hide-amounts"].firstMatch
        XCTAssertTrue(eye.exists, "the earned card has no eye")
        eye.tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "•••"), object: total)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 5), .completed, "the eye should hide the amount: \(total.label)")
        eye.tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", shown), object: total)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 5), .completed, "the eye should show the amount again: \(total.label)")
    }

    // MARK: - Site hours are changed on the site

    func testTheEditorSendsSiteHoursToTheSite() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        openMonthWithTheSiteDay(app)

        let day = app.buttons["day-\(Self.yesterday.key)"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), "yesterday is not in the month")
        app.bringToScreen(day)
        day.tap()
        XCTAssertTrue(app.screen("screen-calendar-day").waitForExistence(timeout: 10), "the day's sheet did not open")

        let edit = app.buttons.matching(identifier: "day-card-edit").firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the day's sheet has no Edit")
        edit.tap()
        XCTAssertTrue(app.buttons["day-editor-save"].firstMatch.waitForExistence(timeout: 10), "the editor did not open")

        // The note, read-only, naming the site; and the way to its day.
        let note = app.descendants(matching: .any)["day-editor-site-note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the editor should say the hours come from the site")
        XCTAssertTrue(note.label.contains("Kaiserstrasse"), "the note should name the site: \(note.label)")
        let open = app.buttons["day-editor-open-site"].firstMatch
        XCTAssertTrue(open.exists, "the note has no button to the site's day")
        XCTAssertTrue(open.label.contains("Kaiserstrasse"), "the button should name the site: \(open.label)")
        // Your own hours can still be added under it: "Add times" on a
        // working day, "I still worked some hours" when yesterday was a day
        // off.
        XCTAssertTrue(
            app.buttons["day-editor-add-hours"].firstMatch.exists
                || app.buttons["day-editor-holiday-worked"].firstMatch.exists,
            "own hours should still be offered"
        )

        open.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 10), "the button did not open the site's day")
    }

    // MARK: - Write today's hours

    func testWriteTodayListsTheSitesAndOpensASiteDay() {
        // Pro, because a second active site is Pro while payments are on.
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-site", "-hours-second-site"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.tab(.calendar).tap()

        let write = app.buttons["today-write-hours"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 10), "with a site, Today should offer Write today's hours")
        app.bringToScreen(write)
        write.tap()
        XCTAssertTrue(app.screen("screen-write-today").waitForExistence(timeout: 10), "the question did not open")

        let first = app.buttons["write-today-site-0"].firstMatch
        let second = app.buttons["write-today-site-1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the sheet lists no site")
        XCTAssertTrue(first.label.contains("Kaiserstrasse"), "the first row should be the sample site: \(first.label)")
        XCTAssertTrue(second.exists, "the second site should be listed too")
        XCTAssertTrue(second.label.contains("Trg Pravde"), "the second row should be the second site: \(second.label)")
        XCTAssertTrue(app.buttons["write-today-own"].firstMatch.exists, "Not on a site should be the last choice")

        first.tap()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 10), "a site should open its day for today")
        XCTAssertTrue(waitUntilGone(app.screen("screen-write-today")), "the question should close behind it")
    }

    func testNotOnASiteOpensYourOwnDay() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-site"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 10))
        app.tab(.calendar).tap()

        let write = app.buttons["today-write-hours"].firstMatch
        XCTAssertTrue(write.waitForExistence(timeout: 10), "with a site, Today should offer Write today's hours")
        app.bringToScreen(write)
        write.tap()
        let own = app.buttons["write-today-own"].firstMatch
        XCTAssertTrue(own.waitForExistence(timeout: 10), "the question has no Not on a site")
        own.tap()
        XCTAssertTrue(app.buttons["day-editor-save"].firstMatch.waitForExistence(timeout: 10), "Not on a site should open today in the editor")
    }
}
