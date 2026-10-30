import XCTest

/// Takes the pictures that go on the App Store listing.
///
/// Not a test of anything, and honest about that — every assertion here is a
/// precondition for the shot being worth keeping, not a claim about the app.
/// It lives in the test target because that is the only thing that can drive a
/// simulator, and because the alternative is hand-entering a month on a device
/// to photograph it, which is the work this app exists to avoid.
///
/// CI exports the attachments; see the "App Store screenshots" step.
///
/// Nothing here is found by its label, because this suite is run twice: once
/// in English and once in German, to produce a set of screenshots per
/// language. A test that waits for `buttons["Calendar"]` passes in one
/// language and hangs in the other.
///
/// The tabs are reached by position rather than by identifier. An
/// `accessibilityIdentifier` on a tab applies to that tab's content view, not
/// to its button in the tab bar, so the identifier is simply never there to
/// find — which is what the first attempt at this discovered, in CI, after a
/// fifteen-second wait and a red run.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Sample data and Pro, because a listing should show the app doing its
    /// job rather than an empty calendar and a row of locks. As shipped, so a
    /// free release shows nothing for sale.
    private func launchForShots() -> XCUIApplication {
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-data", "-hours-as-shipped"]
        app.launch()
        XCTAssertTrue(app.tab(.calendar).waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        taken.append(name)
    }

    /// Settings is taller than a screen, so a row near the bottom has to be
    /// brought up before it can be tapped.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Waits for an element to become enabled — the export's page preview is
    /// a disabled button until the PDF has been drawn, and a shot taken
    /// before then is a grey well.
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }

    /// Which shots actually got taken. The first version of this test wrapped
    /// every capture in `if it exists`, so a screen that failed to open simply
    /// produced no picture and a green tick — four files where five were
    /// expected, and nothing in the log saying which one was missing.
    private var taken: [String] = []

    /// The listing's order, which is the order App Store Connect shows them
    /// in: `fastlane deliver` sorts by filename. `fastlane/screenshots.txt`
    /// carries the same list for the upload, and
    /// `Scripts/check-store-metadata.py` fails when the two differ.
    ///
    /// 1.1's set: the site and its extra work lead, because that is what the
    /// app is for. Numbered with names of their own, because the export
    /// capture tests attach `06-export-pdf-1` and `07-export-pdf-summary` to
    /// the same folder: the upload picks these by name, never by number.
    /// The Apple Watch shots are not taken here (see the "Apple Watch
    /// screenshots" step in ci.yml and `fastlane/watch-screenshots.txt`).
    static let listing = [
        "01-calendar", "02-site", "03-extra-work", "04-extra-work-report",
        "05-site-sheet", "06-day-editor", "07-insights", "08-privacy",
    ]

    func testCaptureTheListing() {
        let app = launchForShots()

        // 1 — the calendar, which is what the app is. A rate is set in the
        // sample data, so the month's summary leads with what it earned.
        capture("01-calendar", app)

        // 2 — the site, which is who the app is for: the week strip and
        // today's card at the top, the crew ticked off once for everyone.
        // Straight after the first capture a tab tap can be lost on a slow
        // runner, and then the list never comes. Tap again if it did not open.
        app.tab(.sites).tap()
        if !app.screen("screen-sites").waitForExistence(timeout: 5) {
            app.tab(.sites).tap()
        }
        XCTAssertTrue(app.screen("screen-sites").waitForExistence(timeout: 10), "the Sites tab did not open")
        let card = app.buttons["site-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the sample site has no card")
        card.tap()
        app.openTodayOnSite()
        XCTAssertTrue(app.screen("screen-site-day").waitForExistence(timeout: 10), "the site did not open")
        XCTAssertTrue(app.descendants(matching: .any)["site-day-times"].waitForExistence(timeout: 5), "today's site card is not written")
        capture("02-site", app)

        // 3 — today's extra work under the site day: the "Extra work"
        // heading with "Send to boss", one job done, one in progress, with
        // their material and who was on them. The heading is scrolled up to
        // just under the navigation bar, so it is not cut off and the jobs
        // fit below it.
        let heading = app.descendants(matching: .any)["extra-work-heading"].firstMatch
        // The day is a list, which only makes the rows on screen: scroll down to it.
        for _ in 0..<8 where !heading.exists { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the site day has no extra work")
        for _ in 0..<6 where !heading.isHittable { app.swipeUp() }
        XCTAssertTrue(heading.isHittable, "could not scroll to the extra work")
        let top = app.navigationBars.firstMatch.frame.maxY + 16
        let from = heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if from.screenPoint.y > top + 8 {
            let to = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: from.screenPoint.x, dy: top))
            // Slow and held, so the scroll stops where the finger does.
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(app.buttons["extra-work-job-1"].waitForExistence(timeout: 5), "today's sample jobs are not listed")
        capture("03-extra-work", app)

        // 4 — the report to the boss: what is done and not sent yet, and the
        // material added up, in the export language. From the site's page.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 10), "could not get back to the site's page")
        app.buttons["site-extra-work-report"].tap()
        XCTAssertTrue(app.screen("screen-extra-work-report").waitForExistence(timeout: 10), "the report did not open")
        XCTAssertTrue(app.buttons["extra-work-report-job-0"].waitForExistence(timeout: 10), "the report has no finished jobs")
        capture("04-extra-work-report", app)
        app.buttons["extra-work-report-done"].tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 10))

        // 5 — the site sheet: last month, one column group per person,
        // previewed as the PDF's first page.
        let export = app.buttons["site-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "the site has no Sheet button")
        export.tap()
        XCTAssertTrue(app.screen("screen-site-export").waitForExistence(timeout: 10), "the site export did not open")
        let page = app.descendants(matching: .any)["export-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the sheet has no page preview")
        XCTAssertTrue(waitUntilEnabled(page, timeout: 15), "the sheet's first page was never drawn")
        capture("05-site-sheet", app)
        app.buttons["export-done"].tap()
        XCTAssertTrue(app.screen("screen-site").waitForExistence(timeout: 10))

        // 6 — a day open, showing what one holds. Today, because the sample
        // month always writes it, and it is the day already selected.
        app.tab(.calendar).tap()
        let save = app.openTodaysEditor()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the day editor did not open")
        capture("06-day-editor", app)
        app.buttons["day-editor-cancel"].tap()

        // 7 — the month's figures, earnings first.
        app.tab(.insights).tap()
        XCTAssertTrue(app.screen("screen-insights").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["insights-earned"].waitForExistence(timeout: 10), "Insights shows no earnings")
        capture("07-insights", app)

        // 8 — the privacy screen, which is the reason to choose this one.
        app.tab(.settings).tap()
        XCTAssertTrue(app.screen("screen-settings").waitForExistence(timeout: 10))
        let privacy = app.buttons["settings-privacy"]
        XCTAssertTrue(app.openSettingsMore(), "Settings has no More row")
        XCTAssertTrue(reveal(privacy, in: app), "could not scroll Settings down to Privacy")
        privacy.tap()
        XCTAssertTrue(app.screen("screen-privacy").waitForExistence(timeout: 10))
        capture("08-privacy", app)

        XCTAssertEqual(taken, Self.listing, "a screenshot is missing")
    }
}
