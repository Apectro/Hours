import XCTest

/// Drives the app the way a person would, slowly enough to watch.
///
/// Not a test. It asserts almost nothing about behaviour and it is skipped by
/// every ordinary run — its only product is the frames underneath it, which CI
/// captures with `simctl io recordVideo` while this is on screen. The pacing
/// exists for the camera: an XCUITest taps as fast as the app will accept
/// taps, and the resulting video is a slideshow of half-drawn transitions.
///
/// Kept in the test target for the same reason the screenshots are: the test
/// runner is the only thing that can drive a simulator.
///
/// Everything is found by accessibility identifier rather than by label, so
/// this records in any of the ten languages the app ships. The tabs go by
/// position, because an `accessibilityIdentifier` on a `TabView` tab lands on
/// the tab's content and not on its button — see `TabBar.swift`.
final class WalkthroughTests: XCTestCase {
    /// Long enough to read what is on screen, short enough that nobody stops
    /// watching. Every pause is a multiple of this rather than a number picked
    /// per call site, so the whole thing speeds up or slows down in one place.
    private static let beat: TimeInterval = 1.4

    /// Which beats actually happened.
    ///
    /// A walkthrough that fails at step three should still produce a video of
    /// steps one and two — a recording that stops early is the most useful
    /// possible bug report. So nothing here aborts the run: the beats are
    /// collected and checked once, at the end, after the camera has seen
    /// everything it is going to see.
    private var visited: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func pause(_ beats: Double = 1) {
        Thread.sleep(forTimeInterval: Self.beat * beats)
    }

    /// Records the beat and says whether to keep going.
    @discardableResult
    private func reached(_ name: String, _ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("the walkthrough never reached \(name)")
            return false
        }
        visited.append(name)
        return true
    }

    /// Settings is taller than a screen; a row near the bottom has to be
    /// brought up before it can be tapped. Swipes rather than a scroll-to,
    /// because the swipes are the part worth filming.
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            pause(0.4)
        }
        return element.exists && element.isHittable
    }

    func testWalkthrough() {
        // Sample data and Pro, so the video shows the app doing its job rather
        // than an empty month and a column of padlocks.
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-sample-data"]
        app.launch()

        // 1 — the calendar, which is what the app is.
        guard reached("calendar", app.tab(.calendar)) else { return }
        pause(2)

        // 2 — a day, opened and closed again. Today, because the sample month
        // is seeded around it and it is the day already selected.
        let save = app.openTodaysEditor()
        if reached("day editor", save, timeout: 10) {
            pause(2)
            // A second block, if the weekday this runs on opens with times on
            // it — the button is not there on a day the schedule leaves blank.
            let add = app.buttons["Add another block"]
            if add.exists, add.isHittable {
                add.tap()
                pause(1.5)
                let remove = app.buttons["Remove this block"].firstMatch
                if remove.waitForExistence(timeout: 3) {
                    remove.tap()
                    pause()
                }
            }
            app.buttons["day-editor-cancel"].tap()
            pause()
        }

        // 3 — the month's figures.
        app.tab(.insights).tap()
        if reached("insights", app.screen("screen-insights")) {
            pause(2)
            app.swipeUp()
            pause(1.5)
        }

        // 4 — settings, which is where the configurability shows.
        app.tab(.settings).tap()
        if reached("settings", app.screen("screen-settings")) {
            pause(1.5)

            // 5 — the privacy screen, which is the reason to choose this one.
            let privacy = app.buttons["settings-privacy"]
            if reveal(privacy, in: app) {
                privacy.tap()
                if reached("privacy", app.screen("screen-privacy")) { pause(2.5) }
            } else {
                XCTFail("could not scroll Settings down to Privacy")
            }
        }

        // 6 — export, reached from the calendar's overflow menu. Last because
        // it is the thing the app charges for.
        app.tab(.calendar).tap()
        _ = app.tab(.calendar).waitForExistence(timeout: 10)
        pause(0.5)
        app.buttons["calendar-more"].tap()
        let exportItem = app.buttons["calendar-export"]
        if exportItem.waitForExistence(timeout: 5) {
            pause()
            exportItem.tap()
            if reached("export", app.screen("screen-export")) { pause(2.5) }
        } else {
            XCTFail("the overflow menu has no Export item")
        }

        // A couple of seconds of the finished screen, so the video does not
        // cut the moment the last tap lands.
        pause(1.5)

        XCTAssertEqual(
            visited,
            ["calendar", "day editor", "insights", "settings", "privacy", "export"],
            "the walkthrough skipped a screen"
        )
    }
}
