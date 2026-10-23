import XCTest

/// A picture of every screen and state the app has, for a design review.
///
/// Not a test, like the walkthrough and the listing's screenshots: its only
/// product is the attachments, named `atlas-NN-<screen>`, which CI exports
/// (the "Screen atlas" step, behind the `screen_atlas` input). The number
/// gives the order the screens were visited in; the name says which screen
/// it is, and is the same in every pass, so the light, dark, large-text and
/// Croatian sets can be laid side by side by name.
///
/// Skipped by every ordinary run. It runs only when the runner's environment
/// carries `HOURS_SCREEN_ATLAS=1` (xcodebuild passes `TEST_RUNNER_`-prefixed
/// variables through to the test runner with the prefix taken off), and
/// `HOURS_ATLAS_ARGUMENTS` adds launch arguments to every launch — the text
/// size and the language of a pass.
///
/// Nothing stops at the first missing element. A screen that cannot be
/// reached is written down and the next one is tried, so one broken step
/// costs one picture (or the pictures behind it), and the list of what was
/// missed is the single failure at the end.
///
/// Everything is found by accessibility identifier, never by label, because
/// one of the passes is in Croatian. Tabs go by position (see `TabBar.swift`),
/// and segmented controls by segment index.
final class ScreenAtlasTests: XCTestCase {
    static let requestVariable = "HOURS_SCREEN_ATLAS"
    static let argumentsVariable = "HOURS_ATLAS_ARGUMENTS"

    private var number = 0
    private var taken: [String] = []
    private var missed: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment[Self.requestVariable] == "1" else {
            throw XCTSkip("The screen atlas runs only when \(Self.requestVariable)=1 is set for the test runner.")
        }
        continueAfterFailure = true
    }

    /// The pass's own launch arguments, e.g. a text size or a language.
    /// Split on whitespace, so `-AppleLanguages (hr)` arrives as two words.
    private var passArguments: [String] {
        (ProcessInfo.processInfo.environment[Self.argumentsVariable] ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    func testScreenAtlas() {
        sampleDataTour()
        paywall()
        firstRun()
        guidedTour()
        emptyStates()

        print("ATLAS_TAKEN \(taken.count): \(taken.joined(separator: ", "))")
        print("ATLAS_MISSED \(missed.count): \(missed.joined(separator: ", "))")
        XCTAssertTrue(missed.isEmpty, "the atlas missed \(missed.count) screen(s): \(missed.joined(separator: "; "))")
    }

    // MARK: - Passes over the app

    /// The whole app with the sample month, Pro on and nothing for sale.
    private func sampleDataTour() {
        let app = launch(["-hours-sample-data"])
        guard app.tab(.calendar).waitForExistence(timeout: 20) else {
            miss("the app did not start with sample data")
            return
        }
        calendarScreens(app)
        siteScreens(app)
        insightsScreens(app)
        settingsScreens(app)
        app.terminate()
    }

    // MARK: Calendar

    private func calendarScreens(_ app: XCUIApplication) {
        app.tab(.calendar).tap()
        pause(1)
        capture("calendar-month", app)

        swipeUp(app)
        capture("calendar-month-summary", app)
        swipeDown(app, times: 3)

        if tap(app.buttons["calendar-more"], "the calendar's menu", app) {
            capture("calendar-menu", app)
            dismissMenu(app)
        }

        // A day other than today, selected: the card under the grid.
        if let key = dayKey(monthsFromNow: 0, day: 3), key != Self.todayKey,
           tap(app.buttons["day-\(key)"], "the 3rd of this month", app) {
            bringIntoView(app.buttons["day-card-edit"], app)
            capture("calendar-selected-day", app)
        }

        // Today's day, written by the sample site.
        let save = app.openTodaysEditor()
        if save.waitForExistence(timeout: 10) {
            capture("day-editor-existing", app)
            swipeUp(app)
            capture("day-editor-existing-lower", app)
            swipeDown(app, times: 2)
            if tap(app.buttons["day-editor-day-type"], "the day type picker", app) {
                capture("day-editor-day-types", app)
                dismissMenu(app)
            }
            close(app, "day-editor-cancel")
        } else {
            miss("day-editor-existing (today's editor did not open)")
        }

        // A new day: next month has nothing in it.
        if tap(app.buttons["calendar-next"], "next month", app),
           let key = dayKey(monthsFromNow: 1, day: 10) {
            let day = app.buttons["day-\(key)"]
            if tap(day, "the 10th of next month", app) {
                capture("calendar-empty-day", app)
                if tap(app.buttons["day-card-edit"], "Add hours on an empty day", app) {
                    capture("day-editor-new", app)
                    if tap(app.buttons["day-editor-add-hours"], "Add hours in the editor", app) {
                        capture("day-editor-new-times", app)
                        let addBreak = app.buttons["day-editor-add-break"]
                        if addBreak.exists { tapAnyway(addBreak) }
                        bringIntoView(app.buttons["day-editor-add-block"], app)
                        capture("day-editor-breaks", app)
                        if tap(app.buttons["day-editor-add-block"], "Add another block", app) {
                            capture("day-editor-two-blocks", app)
                        }
                    }
                    close(app, "day-editor-cancel")
                }
            }
            tap(app.buttons["calendar-previous"], "back to this month", app)
        }

        // The public holiday the sample month has, and "I worked".
        let holidayDay = Self.today.day == 15 ? 16 : 15
        if let key = dayKey(monthsFromNow: 0, day: holidayDay),
           tap(app.buttons["day-\(key)"], "the public holiday", app) {
            bringIntoView(app.buttons["day-card-holiday-worked"], app)
            capture("calendar-holiday", app)
            if tap(app.buttons["day-card-holiday-worked"], "I worked this day", app) {
                capture("day-editor-holiday-worked", app)
                close(app, "day-editor-cancel")
            }
        }

        // The week of leave: the 8th to the 12th, once they have passed.
        if let key = dayKey(monthsFromNow: 0, day: 10),
           tap(app.buttons["day-\(key)"], "a day of leave", app) {
            bringIntoView(app.buttons["day-card-edit"], app)
            capture("calendar-leave-day", app)
            if tap(app.buttons["day-card-edit"], "the leave day's editor", app) {
                capture("day-editor-leave", app)
                close(app, "day-editor-cancel")
            }
        }

        // Range editing, from the menu.
        if tap(app.buttons["calendar-more"], "the calendar's menu", app),
           tap(app.buttons["calendar-edit-range"], "Edit a range", app) {
            capture("bulk-edit", app)
            close(app, "bulk-edit-cancel")
        }

        // Your own timesheet, in each format.
        if tap(app.buttons["calendar-more"], "the calendar's menu", app),
           tap(app.buttons["calendar-export"], "Export", app) {
            exportScreens(app, prefix: "export")
            close(app, "export-done")
        }
    }

    /// The export screen in each format and the PDF at full size. Shared by
    /// the personal and the site export.
    private func exportScreens(_ app: XCUIApplication, prefix: String) {
        let pdf = app.buttons["export-format-pdf"]
        if pdf.waitForExistence(timeout: 10) { tapAnyway(pdf) }
        let page = app.descendants(matching: .any)["export-preview-page"]
        if page.waitForExistence(timeout: 10) { _ = waitUntilEnabled(page, timeout: 15) }
        capture("\(prefix)-pdf", app)
        if page.exists, page.isEnabled {
            tapAnyway(page)
            pause(1.5)
            capture("\(prefix)-pdf-full-page", app)
            close(app, "export-full-page-done")
        } else {
            miss("\(prefix)-pdf-full-page (the page was never drawn)")
        }
        for format in ["xlsx", "csv"] {
            let card = app.buttons["export-format-\(format)"]
            if bringIntoView(card, app) {
                tapAnyway(card)
                pause(1)
                swipeDown(app, times: 2)
                capture("\(prefix)-\(format)", app)
            } else {
                miss("\(prefix)-\(format) (no format card)")
            }
        }
        if bringIntoView(pdf, app) { tapAnyway(pdf) }
        swipeDown(app, times: 2)
    }

    // MARK: Sites

    private func siteScreens(_ app: XCUIApplication) {
        app.tab(.sites).tap()
        if !app.screen("screen-sites").waitForExistence(timeout: 5) { app.tab(.sites).tap() }
        guard app.buttons["site-card"].firstMatch.waitForExistence(timeout: 15) else {
            miss("sites-list (the sample sites have no cards)")
            return
        }
        capture("sites-list", app)

        if tap(app.buttons["sites-add"], "Add a site", app) {
            capture("site-new", app)
            close(app, "site-editor-cancel")
        }

        tapAnyway(app.buttons["site-card"].firstMatch)
        guard app.screen("screen-site-day").waitForExistence(timeout: 10) else {
            miss("site-day (the site did not open)")
            return
        }
        pause(1)
        capture("site-day-top", app)
        siteDayScreens(app)
        extraWorkScreens(app)
        siteMenuScreens(app)

        // Archived: the second site put away, its day as an archived site
        // shows it, and the list with the folded section underneath.
        back(app)
        let second = app.buttons["site-card"].element(boundBy: 1)
        if tap(second, "the second site", app),
           tap(app.buttons["site-more"], "the site's menu", app),
           tap(app.buttons["site-edit"], "Edit site", app) {
            let archived = app.switches["site-editor-archived"]
            if archived.waitForExistence(timeout: 5) {
                flip(archived)
                tap(app.buttons["site-editor-save"], "Save the site", app)
                pause(1)
                capture("site-archived-day", app)
            } else {
                miss("site-archived-day (no Archived switch)")
                close(app, "site-editor-cancel")
            }
            back(app)
            pause(1)
            capture("sites-list-archived", app)
            let folded = app.descendants(matching: .any)["sites-archived"].firstMatch
            if tap(folded, "the Archived section", app) {
                pause(0.5)
                capture("sites-list-archived-open", app)
            }
        }
    }

    /// Today on the showcase site, from the top to the diary.
    private func siteDayScreens(_ app: XCUIApplication) {
        swipeUp(app)
        capture("site-day-crew", app)

        let times = app.descendants(matching: .any)["site-day-times"].firstMatch
        if tap(times, "the site's times", app) {
            capture("site-times", app)
            close(app, "site-hours-cancel")
        }

        let ivan = app.buttons["site-times-Ivan"]
        if tap(ivan, "Ivan's times", app) {
            capture("site-person-times", app)
            close(app, "person-times-cancel")
        }

        let weather = app.buttons["site-weather-menu"]
        if tap(weather, "the rained-off menu", app) {
            capture("site-rained-off-menu", app)
            if tap(app.buttons["site-weather-stop-at"], "Stopped at", app) {
                capture("site-rained-off-sheet", app)
                close(app, "site-weather-stop-cancel")
            } else {
                dismissMenu(app)
            }
        }

        let addExtraWork = app.buttons["extra-work-add"]
        if bringIntoView(addExtraWork, app) {
            capture("site-day-extra-work", app)
        } else {
            miss("site-day-extra-work (no extra work section)")
        }

        let diary = app.buttons["diary-section-weather"]
        if bringIntoView(diary, app) {
            capture("site-day-diary", app)
            tapAnyway(diary)
            pause(0.5)
            swipeUp(app)
            capture("site-day-diary-open", app)
            if bringIntoView(diary, app) { tapAnyway(diary) }
        } else {
            miss("site-day-diary (no diary on the site day)")
        }
    }

    /// The extra-work editor, new and existing, and the report to the boss.
    private func extraWorkScreens(_ app: XCUIApplication) {
        let editor = app.screen("screen-extra-work-editor")
        let addExtraWork = app.buttons["extra-work-add"]
        if bringIntoView(addExtraWork, app) {
            tapAnyway(addExtraWork)
            if editor.waitForExistence(timeout: 10) {
                pause(0.5)
                capture("extra-work-new", app)
                for section in ["time", "photos", "signature"] {
                    let header = app.buttons["extra-work-section-\(section)"]
                    if bringIntoView(header, app) { tapAnyway(header) }
                }
                swipeDown(app, times: 3)
                capture("extra-work-new-open", app)
                swipeUp(app)
                capture("extra-work-new-open-lower", app)

                if tap(app.buttons["extra-work-new-item"], "New item", app) {
                    capture("extra-work-new-item", app)
                    close(app, "extra-work-item-cancel")
                }
                if tap(app.buttons["extra-work-sign"], "the client's signature", app) {
                    capture("extra-work-client-signature", app)
                    close(app, "extra-work-signature-cancel")
                }
                if tap(app.buttons["extra-work-edit-items"], "the item list", app) {
                    capture("extra-work-catalogue", app)
                    if tap(app.buttons["extra-work-catalog-item"].firstMatch, "an item in the list", app) {
                        capture("extra-work-catalogue-item", app)
                        close(app, "extra-work-item-cancel")
                    }
                    back(app)
                }
                close(app, "extra-work-cancel")
            } else {
                miss("extra-work-new (the editor did not open)")
            }
        }

        for index in 0..<2 {
            let job = app.buttons["extra-work-job-\(index)"]
            if bringIntoView(job, app) {
                tapAnyway(job)
                if editor.waitForExistence(timeout: 10) {
                    pause(0.5)
                    capture("extra-work-existing-\(index + 1)", app)
                    swipeUp(app)
                    capture("extra-work-existing-\(index + 1)-lower", app)
                    close(app, "extra-work-cancel")
                } else {
                    miss("extra-work-existing-\(index + 1) (the job did not open)")
                }
            } else {
                miss("extra-work-existing-\(index + 1) (no job \(index) today)")
            }
        }

        swipeDown(app, times: 8)
        if tap(app.buttons["site-extra-work-report"], "the report to the boss", app),
           app.screen("screen-extra-work-report").waitForExistence(timeout: 10) {
            pause(1)
            capture("extra-work-report", app)
            let inProgress = app.switches["extra-work-report-include-in-progress"]
            if inProgress.waitForExistence(timeout: 5) {
                flip(inProgress)
                pause(0.5)
                capture("extra-work-report-in-progress", app)
                swipeUp(app)
                capture("extra-work-report-lower", app)
                if tap(app.buttons["extra-work-report-sign"], "the report's signature", app) {
                    capture("extra-work-report-signature", app)
                    close(app, "extra-work-signature-cancel")
                }
                swipeDown(app, times: 4)
                flip(inProgress)
            } else {
                miss("extra-work-report-in-progress (no switch)")
            }
            let range = app.segmentedControls["extra-work-report-range"]
            if range.waitForExistence(timeout: 5), range.buttons.count > 2 {
                range.buttons.element(boundBy: 2).tap()
                pause(0.5)
                capture("extra-work-report-dates", app)
                range.buttons.element(boundBy: 0).tap()
            } else {
                miss("extra-work-report-dates (no range control)")
            }
            close(app, "extra-work-report-done")
        }
    }

    /// Everything behind the site's menu: crew, diary, export and sign-off,
    /// and the site's own editor.
    private func siteMenuScreens(_ app: XCUIApplication) {
        swipeDown(app, times: 8)
        if tap(app.buttons["site-more"], "the site's menu", app) {
            capture("site-menu", app)
            if tap(app.buttons["site-crew"], "the crew", app),
               app.screen("screen-crew").waitForExistence(timeout: 10) {
                pause(0.5)
                capture("crew", app)
                let member = app.descendants(matching: .any)["crew-member"].firstMatch
                if member.waitForExistence(timeout: 5) {
                    member.press(forDuration: 1.2)
                    pause(1)
                    capture("crew-member-menu", app)
                    if tap(app.buttons["crew-rename"], "Rename", app) {
                        pause(0.5)
                        capture("crew-member-rename", app)
                        let cancel = app.buttons["crew-rename-cancel"]
                        if cancel.waitForExistence(timeout: 2) {
                            cancel.tap()
                        } else if app.alerts.firstMatch.exists {
                            // Save with the name unchanged is as harmless as Cancel.
                            app.alerts.firstMatch.buttons.firstMatch.tap()
                        }
                    } else {
                        dismissMenu(app)
                    }
                } else {
                    miss("crew-member-menu (no crew member)")
                }
                if tap(app.buttons["crew-add-from-sites"], "Add from other sites", app) {
                    capture("crew-add-from-other-sites", app)
                    close(app, "crew-picker-cancel")
                }
                back(app)
            }
        }

        if tap(app.buttons["site-more"], "the site's menu", app),
           tap(app.buttons["site-diary-list"], "the site diary", app) {
            pause(1)
            capture("site-diary-list", app)
            close(app, "site-diary-list-done")
        }

        if tap(app.buttons["site-more"], "the site's menu", app),
           tap(app.buttons["site-export"], "the site's export", app),
           app.screen("screen-site-export").waitForExistence(timeout: 10) {
            exportScreens(app, prefix: "site-export")
            let signOff = app.buttons["export-sign-off"]
            if bringIntoView(signOff, app) {
                tapAnyway(signOff)
                if app.screen("screen-sign-off").waitForExistence(timeout: 10) {
                    pause(1)
                    capture("site-sign-off", app)
                    let person = app.buttons.matching(
                        NSPredicate(format: "identifier BEGINSWITH %@", "sign-off-person-")
                    ).firstMatch
                    if tap(person, "a person to sign", app) {
                        pause(0.5)
                        capture("site-signing", app)
                        let canvas = app.descendants(matching: .any)["signature-canvas"].firstMatch
                        if canvas.waitForExistence(timeout: 5) {
                            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.6))
                            let middle = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                            let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
                            start.press(forDuration: 0.1, thenDragTo: middle)
                            middle.press(forDuration: 0.1, thenDragTo: end)
                            pause(0.5)
                            capture("site-signing-drawn", app)
                        } else {
                            miss("site-signing-drawn (no signature area)")
                        }
                        close(app, "signature-cancel")
                    }
                    back(app)
                } else {
                    miss("site-sign-off (the sign-off did not open)")
                }
            } else {
                miss("site-sign-off (no Crew sign-off row)")
            }
            close(app, "export-done")
        }

        if tap(app.buttons["site-more"], "the site's menu", app),
           tap(app.buttons["site-edit"], "Edit site", app) {
            capture("site-edit", app)
            close(app, "site-editor-cancel")
        }
    }

    // MARK: Insights

    private func insightsScreens(_ app: XCUIApplication) {
        app.tab(.insights).tap()
        guard app.screen("screen-insights").waitForExistence(timeout: 10) else {
            miss("insights (the tab did not open)")
            return
        }
        pause(1)
        capture("insights-month", app)
        swipeUp(app)
        capture("insights-month-lower", app)
        swipeUp(app)
        capture("insights-month-bottom", app)
        swipeDown(app, times: 4)

        let scope = scopeControl(app)
        guard scope.waitForExistence(timeout: 5), scope.buttons.count >= 4 else {
            miss("insights periods (no period control)")
            return
        }
        for (index, name) in [(0, "insights-today"), (1, "insights-week"), (3, "insights-year")] {
            scope.buttons.element(boundBy: index).tap()
            pause(1)
            capture(name, app)
        }
        swipeUp(app)
        capture("insights-year-lower", app)

        if bringIntoView(app.descendants(matching: .any)["insights-leave"].firstMatch, app) {
            capture("insights-leave-balance", app)
        } else {
            miss("insights-leave-balance (no leave card)")
        }

        let review = app.buttons["insights-year-review"]
        if bringIntoView(review, app) {
            tapAnyway(review)
            if app.buttons["year-review-close"].waitForExistence(timeout: 10) {
                pause(1.5)
                capture("year-in-review", app)
                swipeUp(app)
                pause(0.5)
                capture("year-in-review-lower", app)
                app.buttons["year-review-close"].tap()
                pause(1)
            } else {
                miss("year-in-review (did not open)")
            }
        } else {
            miss("year-in-review (no button)")
        }
        swipeDown(app, times: 4)
        if scope.exists { scope.buttons.element(boundBy: 2).tap() }
    }

    private func scopeControl(_ app: XCUIApplication) -> XCUIElement {
        let named = app.segmentedControls["insights-scope"]
        return named.exists ? named : app.segmentedControls.firstMatch
    }

    // MARK: Settings

    private func settingsScreens(_ app: XCUIApplication) {
        app.tab(.settings).tap()
        guard app.screen("screen-settings").waitForExistence(timeout: 10) else {
            miss("settings (the tab did not open)")
            return
        }
        pause(1)

        // The root, a screen height at a time, until the last row is up.
        capture("settings-1", app)
        let last = app.buttons["settings-show-tour"]
        var page = 1
        while page < 5, !(last.exists && last.isHittable) {
            swipeUp(app)
            page += 1
            capture("settings-\(page)", app)
        }
        swipeDown(app, times: 6)

        settingsPage("settings-schedule", "settings-schedule", app)
        settingsPage("settings-leave", "settings-leave", app)
        settingsPage("settings-pay", "settings-pay", app) {
            self.swipeUp(app)
            self.capture("settings-pay-lower", app)
        }
        settingsPage("settings-jobs", "settings-jobs", app) {
            if self.tap(app.buttons["jobs-row"].firstMatch, "a job", app) {
                self.capture("settings-job-editor", app)
                self.close(app, "job-editor-cancel")
            }
            if self.tap(app.buttons["jobs-add"], "Add a job", app) {
                self.capture("settings-job-new", app)
                self.close(app, "job-editor-cancel")
            }
        }
        settingsPage("settings-calculation", "settings-calculation", app) {
            self.swipeUp(app)
            self.capture("settings-calculation-lower", app)
        }
        settingsPage("settings-fields", "settings-fields", app)
        settingsPage("settings-day-types", "settings-day-types", app) {
            if self.tap(app.buttons["day-types-row"].firstMatch, "a day type", app) {
                self.capture("settings-day-type-editor", app)
                self.close(app, "day-type-editor-cancel")
            }
            if self.tap(app.buttons["day-types-add"], "Add a day type", app) {
                self.capture("settings-day-type-new", app)
                self.close(app, "day-type-editor-cancel")
            }
        }
        settingsPage("settings-reminders", "settings-reminders", app) {
            self.swipeUp(app)
            self.capture("settings-reminders-lower", app)
        }
        settingsPage("settings-holidays", "settings-holidays", app) {
            if self.tap(app.buttons["holidays-row"].firstMatch, "a holiday", app) {
                self.capture("settings-holiday-editor", app)
                self.close(app, "holiday-editor-cancel")
            }
            if self.tap(app.buttons["holidays-add"], "Add a holiday", app) {
                self.capture("settings-holiday-new", app)
                self.close(app, "holiday-editor-cancel")
            }
            if self.tap(app.buttons["public-holidays-open"], "Add public holidays", app) {
                self.publicHolidayPicker(app, prefix: "settings-public-holidays")
            }
        }
        settingsPage("settings-calendar", "settings-calendar", app)
        settingsPage("settings-theme", "settings-theme", app)
        settingsPage("settings-export-options", "settings-export-options", app) {
            self.swipeUp(app)
            self.capture("settings-export-options-lower", app)
        }
        settingsPage("settings-icloud", "settings-icloud", app)
        settingsPage("settings-data", "settings-backup-and-data", app)
        settingsPage("settings-privacy", "settings-privacy", app) {
            self.swipeUp(app)
            self.capture("settings-privacy-lower", app)
        }
    }

    /// The countries, a country's regions, and a set before it is added.
    /// Cancelled, so nothing is added.
    private func publicHolidayPicker(_ app: XCUIApplication, prefix: String) {
        let germany = app.buttons["public-holidays-country-de"]
        guard germany.waitForExistence(timeout: 10) else {
            miss("\(prefix) (the countries were not listed)")
            return
        }
        pause(0.5)
        capture(prefix, app)
        tapAnyway(germany)
        pause(1)
        capture("\(prefix)-regions", app)
        back(app)
        let austria = app.buttons["public-holidays-country-at"]
        if tap(austria, "Austria", app), app.buttons["public-holidays-add"].waitForExistence(timeout: 5) {
            pause(0.5)
            capture("\(prefix)-preview", app)
            back(app)
        } else {
            miss("\(prefix)-preview (the preview did not open)")
        }
        close(app, "public-holidays-cancel")
    }

    /// One row of Settings: opened, captured, anything under it, and back.
    private func settingsPage(
        _ identifier: String,
        _ name: String,
        _ app: XCUIApplication,
        deeper: (() -> Void)? = nil
    ) {
        let row = app.buttons[identifier]
        guard bringIntoView(row, app) else {
            miss("\(name) (no row \(identifier))")
            return
        }
        tapAnyway(row)
        pause(1)
        capture(name, app)
        deeper?()
        back(app)
        pause(0.5)
    }

    // MARK: - Separate launches

    /// The Pro screen, which a free release never shows: unpaid, and with
    /// payments switched on as a TestFlight build has them.
    private func paywall() {
        let app = XCUIApplication.hours(pro: false)
        app.launchArguments += passArguments
        app.launch()
        guard app.tab(.settings).waitForExistence(timeout: 20) else {
            miss("paywall (the app did not start)")
            return
        }
        app.tab(.settings).tap()
        if tap(app.buttons["settings-pro"], "the Pro row", app) {
            pause(1.5)
            capture("paywall", app)
            swipeUp(app)
            capture("paywall-lower", app)
            close(app, "paywall-not-now")
        }
        app.terminate()
    }

    /// The first-run questions, one picture per step.
    private func firstRun() {
        let app = launch(["-hours-first-run"])
        let steps = ["name", "week", "breaks", "holidays", "language", "crew", "pay", "finish"]
        for (index, step) in steps.enumerated() {
            let screen = app.screen("screen-setup-\(step)")
            guard screen.waitForExistence(timeout: 10) else {
                miss("setup-\(step) (did not come)")
                break
            }
            pause(1)
            if step == "crew", app.buttons["setup-crew-yes"].exists {
                // A crew lead: the last step then offers to create a site.
                app.buttons["setup-crew-yes"].tap()
                pause(0.5)
            }
            capture("setup-\(index + 1)-\(step)", app)
            guard step != "finish" else { break }
            let next = app.buttons["setup-continue"]
            if waitUntilHittable(next, timeout: 5) {
                next.tap()
            } else if step == "name", app.textFields["setup-name"].exists {
                // The keyboard can cover Continue; Return continues as well.
                app.textFields["setup-name"].typeText("\n")
            } else {
                miss("setup-\(step) (no Continue)")
                break
            }
        }
        app.terminate()
    }

    /// The guided tour over the sample month, one picture per stop: Next
    /// until a stop offers Done instead, however many stops there are.
    private func guidedTour() {
        let app = launch(["-hours-sample-data", "-hours-tour"])
        for stop in 1...10 {
            let card = app.descendants(matching: .any)["tour-card"].firstMatch
            guard card.waitForExistence(timeout: 15) else {
                miss("tour-\(stop) (no tour card)")
                break
            }
            pause(1.5)
            capture("tour-\(stop)", app)
            let next = app.buttons["tour-next"]
            let done = app.buttons["tour-done"]
            if waitUntilHittable(next, timeout: 5) {
                next.tap()
            } else if done.exists {
                tapAnyway(done)
                break
            } else {
                miss("tour-\(stop + 1) (neither Next nor Done on stop \(stop))")
                break
            }
        }
        app.terminate()
    }

    /// A fresh install with nothing in it, then one site with nothing on it.
    private func emptyStates() {
        let app = launch([])
        guard app.tab(.calendar).waitForExistence(timeout: 20) else {
            miss("empty states (the app did not start)")
            return
        }
        pause(1)
        capture("empty-calendar", app)

        app.tab(.sites).tap()
        if app.screen("screen-sites").waitForExistence(timeout: 10) {
            pause(1)
            capture("empty-sites", app)
        } else {
            miss("empty-sites (the tab did not open)")
        }

        app.tab(.insights).tap()
        if app.screen("screen-insights").waitForExistence(timeout: 10) {
            pause(1)
            capture("empty-insights", app)
            let scope = scopeControl(app)
            if scope.waitForExistence(timeout: 5), scope.buttons.count >= 4 {
                scope.buttons.element(boundBy: 3).tap()
                pause(0.5)
                let review = app.buttons["insights-year-review"]
                if bringIntoView(review, app) {
                    tapAnyway(review)
                    if app.buttons["year-review-close"].waitForExistence(timeout: 10) {
                        pause(1)
                        capture("empty-year-in-review", app)
                        app.buttons["year-review-close"].tap()
                    } else {
                        miss("empty-year-in-review (did not open)")
                    }
                }
            }
        } else {
            miss("empty-insights (the tab did not open)")
        }
        app.terminate()

        // One site, its crew, yesterday written and nothing else: today
        // offers "Same as last day", and the report has nothing to say.
        let siteApp = launch(["-hours-sample-site"])
        guard siteApp.tab(.sites).waitForExistence(timeout: 20) else {
            miss("empty site (the app did not start)")
            return
        }
        siteApp.tab(.sites).tap()
        if tap(siteApp.buttons["site-card"].firstMatch, "the sample site", siteApp),
           siteApp.screen("screen-site-day").waitForExistence(timeout: 10) {
            pause(1)
            capture("empty-site-day-unwritten", siteApp)
            if bringIntoView(siteApp.buttons["extra-work-add"], siteApp) {
                capture("empty-site-day-extra-work", siteApp)
            }
            swipeDown(siteApp, times: 6)
            if tap(siteApp.buttons["site-extra-work-report"], "the empty report", siteApp),
               siteApp.screen("screen-extra-work-report").waitForExistence(timeout: 10) {
                pause(1)
                capture("empty-extra-work-report", siteApp)
                close(siteApp, "extra-work-report-done")
            }
        } else {
            miss("empty-site-day-unwritten (the site did not open)")
        }
        siteApp.terminate()
    }

    // MARK: - Helpers

    /// Sample data or not, Pro on and as shipped, so nothing is gated and
    /// nothing is for sale; plus the pass's own arguments.
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication.hours(pro: true)
        app.launchArguments += ["-hours-as-shipped"] + arguments + passArguments
        app.launch()
        return app
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Takes the picture. The number is the order of the visit; the name is
    /// what the screen is.
    private func capture(_ name: String, _ app: XCUIApplication) {
        number += 1
        // Long enough for a push, a sheet or a menu to finish arriving.
        pause(0.8)
        let padded = number < 10 ? "0\(number)" : "\(number)"
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "atlas-\(padded)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        taken.append(name)
    }

    /// Written down, and the atlas goes on.
    private func miss(_ what: String) {
        missed.append(what)
        print("ATLAS_MISS \(what)")
    }

    /// Waits for an element, brings it on screen and taps it; or writes down
    /// that it was not there. Returns whether it was tapped.
    @discardableResult
    private func tap(_ element: XCUIElement, _ what: String, _ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            miss(what)
            return false
        }
        if !element.isHittable { bringIntoView(element, app) }
        tapAnyway(element)
        pause(0.6)
        return true
    }

    /// A tap that does not fail the run on an element XCTest calls not
    /// hittable (one half under a toolbar, say): its centre is tapped instead.
    private func tapAnyway(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// A switch, by its switch rather than the middle of its row, which on
    /// a full-width toggle is the label.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists, inner.isHittable {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    /// Scrolls until the element is on screen: up first, then back down.
    @discardableResult
    private func bringIntoView(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        if element.exists, element.isHittable { return true }
        for _ in 0..<6 {
            app.swipeUp()
            pause(0.3)
            if element.exists, element.isHittable { return true }
        }
        for _ in 0..<10 {
            app.swipeDown()
            pause(0.3)
            if element.exists, element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    private func swipeUp(_ app: XCUIApplication) {
        app.swipeUp()
        pause(0.5)
    }

    private func swipeDown(_ app: XCUIApplication, times: Int) {
        for _ in 0..<times { app.swipeDown() }
        pause(0.4)
    }

    /// Closes a sheet by its button; if the button is not there, by a swipe
    /// down from the top of the screen, so the next screen is not stuck
    /// behind a sheet that would not close.
    private func close(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 3) {
            tapAnyway(button)
        } else {
            miss("could not close with \(identifier)")
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        pause(1)
    }

    /// Back, with the topmost navigation bar's first button.
    private func back(_ app: XCUIApplication) {
        let bars = app.navigationBars
        let count = bars.count
        guard count > 0 else { return }
        let backButton = bars.element(boundBy: count - 1).buttons.element(boundBy: 0)
        if backButton.exists {
            tapAnyway(backButton)
            pause(0.8)
        }
    }

    /// A menu is closed by a tap anywhere outside it: here, the status bar.
    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()
        pause(0.6)
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    // MARK: - Dates

    private static var today: DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: Date())
    }

    private static var todayKey: Int { XCUIApplication.todayKey }

    /// `yyyyMMdd` for a day in this month or a later one, the key the
    /// calendar's cells are identified by; nil for a day the month lacks.
    private func dayKey(monthsFromNow: Int, day: Int) -> Int? {
        let calendar = Calendar.current
        guard let firstOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
              let first = calendar.date(byAdding: .month, value: monthsFromNow, to: firstOfThisMonth),
              let days = calendar.range(of: .day, in: .month, for: first),
              days.contains(day) else {
            return nil
        }
        let parts = calendar.dateComponents([.year, .month], from: first)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + day
    }
}
