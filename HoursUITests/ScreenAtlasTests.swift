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
    /// Pictures that depend on the simulator rather than the app (a photo
    /// from the system picker): written down, but not a failure.
    private var optional: [String] = []

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
        print("ATLAS_OPTIONAL_MISSED \(optional.count): \(optional.joined(separator: ", "))")
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
        allowanceScreens(app)
        closedMonthScreens(app)
        app.terminate()
    }

    // MARK: Calendar

    private func calendarScreens(_ app: XCUIApplication) {
        app.tab(.calendar).tap()
        pause(1)
        capture("calendar-today", app)

        // The month, under Today.
        swipeUp(app)
        capture("calendar-month", app)
        swipeUp(app)
        capture("calendar-month-summary", app)
        swipeDown(app, times: 4)

        if tap(app.buttons.matching(identifier: "calendar-more").firstMatch, "the calendar's menu", app) {
            capture("calendar-menu", app)
            dismissMenu(app)
        }

        // A day other than today, opened from the month.
        if let key = dayKey(monthsFromNow: 0, day: 3), key != Self.todayKey,
           tap(app.buttons.matching(identifier: "day-\(key)").firstMatch, "the 3rd of this month", app) {
            capture("calendar-selected-day", app)
            back(app)
        }

        // Today's day, written by the sample site.
        let save = app.openTodaysEditor()
        if save.waitForExistence(timeout: 10) {
            capture("day-editor-existing", app)
            swipeUp(app)
            capture("day-editor-existing-lower", app)
            if tap(app.buttons.matching(identifier: "day-editor-more").firstMatch, "Allowance, km, note…", app) {
                capture("day-editor-extras", app)
                close(app, "day-extras-done")
            }
            swipeDown(app, times: 2)
            if tap(app.buttons.matching(identifier: "day-editor-day-type").firstMatch, "the day type picker", app) {
                capture("day-editor-day-types", app)
                dismissMenu(app)
            }
            close(app, "day-editor-cancel")
        } else {
            miss("day-editor-existing (today's editor did not open)")
        }
        back(app)

        // A new day: next month has nothing in it.
        bringIntoView(app.buttons.matching(identifier: "calendar-next").firstMatch, app)
        if tap(app.buttons.matching(identifier: "calendar-next").firstMatch, "next month", app),
           let key = dayKey(monthsFromNow: 1, day: 10) {
            let day = app.buttons.matching(identifier: "day-\(key)").firstMatch
            if tap(day, "the 10th of next month", app) {
                capture("calendar-empty-day", app)
                if tap(app.buttons.matching(identifier: "day-card-edit").firstMatch, "Add hours on an empty day", app) {
                    capture("day-editor-new", app)
                    if tap(app.buttons.matching(identifier: "day-editor-add-hours").firstMatch, "Add hours in the editor", app) {
                        capture("day-editor-new-times", app)
                        let addBreak = app.buttons.matching(identifier: "day-editor-add-break").firstMatch
                        if addBreak.exists { tapAnyway(addBreak) }
                        bringIntoView(app.buttons.matching(identifier: "day-editor-add-block").firstMatch, app)
                        capture("day-editor-breaks", app)
                        if tap(app.buttons.matching(identifier: "day-editor-add-block").firstMatch, "Add another block", app) {
                            capture("day-editor-two-blocks", app)
                        }
                    }
                    // Away: the day types as a grid.
                    swipeDown(app, times: 3)
                    let kind = app.segmentedControls.matching(identifier: "day-editor-kind").firstMatch
                    if kind.waitForExistence(timeout: 3), kind.buttons.count > 1 {
                        tapAnyway(kind.buttons.element(boundBy: 1))
                        pause(0.6)
                        capture("day-editor-away", app)
                    } else {
                        miss("day-editor-away (no Worked · Away · Day off)")
                    }
                    close(app, "day-editor-cancel")
                    if app.buttons.matching(identifier: "day-editor-discard").firstMatch.waitForExistence(timeout: 2) {
                        tapAnyway(app.buttons.matching(identifier: "day-editor-discard").firstMatch)
                        pause(1)
                    }
                }
                back(app)
            }
            tap(app.buttons.matching(identifier: "calendar-previous").firstMatch, "back to this month", app)
        }

        // The public holiday the sample month has, and "I worked".
        let holidayDay = Self.today.day == 15 ? 16 : 15
        if let key = dayKey(monthsFromNow: 0, day: holidayDay),
           tap(app.buttons.matching(identifier: "day-\(key)").firstMatch, "the public holiday", app) {
            bringIntoView(app.buttons.matching(identifier: "day-card-holiday-worked").firstMatch, app)
            capture("calendar-holiday", app)
            if tap(app.buttons.matching(identifier: "day-card-holiday-worked").firstMatch, "I worked this day", app) {
                capture("day-editor-holiday-worked", app)
                close(app, "day-editor-cancel")
            }
            back(app)
        }

        // The week of leave: the 8th to the 12th, once they have passed.
        if let key = dayKey(monthsFromNow: 0, day: 10),
           tap(app.buttons.matching(identifier: "day-\(key)").firstMatch, "a day of leave", app) {
            capture("calendar-leave-day", app)
            if tap(app.buttons.matching(identifier: "day-card-edit").firstMatch, "the leave day's editor", app) {
                capture("day-editor-leave", app)
                close(app, "day-editor-cancel")
            }
            back(app)
        }

        // Range editing, from its button under the month.
        if tap(app.buttons.matching(identifier: "calendar-edit-range").firstMatch, "Edit a range", app) {
            capture("bulk-edit", app)
            close(app, "bulk-edit-cancel")
        }

        // The closed months, from the menu.
        swipeDown(app, times: 4)
        if tap(app.buttons.matching(identifier: "calendar-more").firstMatch, "the calendar's menu", app),
           tap(app.buttons.matching(identifier: "calendar-closed-months").firstMatch, "Closed months", app) {
            capture("calendar-closed-months", app)
            back(app)
        }

        // Your own timesheet, in each format: Export under the month.
        if tap(app.buttons.matching(identifier: "calendar-export").firstMatch, "Export", app) {
            exportScreens(app, prefix: "export")
            close(app, "export-done")
        }
        swipeDown(app, times: 4)
    }

    /// The export screen (1.2 redesign): the preview, the PDF at full size,
    /// PDF and Excel ready to send, and This sheet with the CSV. Shared by
    /// the personal and the site export.
    private func exportScreens(_ app: XCUIApplication, prefix: String) {
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
        for format in ["pdf", "xlsx"] {
            let button = app.buttons.matching(identifier: "export-format-\(format)").firstMatch
            if tap(button, "the \(format) button", app) {
                answerNameIfAsked(app)
                if app.buttons.matching(identifier: "export-share").firstMatch.waitForExistence(timeout: 10) {
                    pause(1)
                    capture("\(prefix)-\(format)", app)
                    close(app, "export-full-page-done")
                } else {
                    miss("\(prefix)-\(format) (nothing ready to send)")
                }
            }
        }
        if tap(app.buttons.matching(identifier: "export-this-sheet").firstMatch, "This sheet", app) {
            pause(0.8)
            capture("\(prefix)-this-sheet", app)
            if tap(app.buttons.matching(identifier: "export-format-csv").firstMatch, "CSV file", app),
               app.buttons.matching(identifier: "export-share").firstMatch.waitForExistence(timeout: 10) {
                pause(1)
                capture("\(prefix)-csv", app)
                close(app, "export-full-page-done")
            }
            back(app)
        }
        swipeDown(app, times: 2)
    }

    /// The name on the sheet is asked for once, at the first file; any of
    /// its buttons answers it.
    private func answerNameIfAsked(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            capture("export-name-alert", app)
            alert.buttons.firstMatch.tap()
            pause(1)
        }
    }

    // MARK: Sites

    private func siteScreens(_ app: XCUIApplication) {
        app.tab(.sites).tap()
        if !app.screen("screen-sites").waitForExistence(timeout: 5) { app.tab(.sites).tap() }
        guard app.buttons.matching(identifier: "site-card").firstMatch.waitForExistence(timeout: 15) else {
            miss("sites-list (the sample sites have no cards)")
            return
        }
        capture("sites-list", app)

        newSiteWizardScreens(app)

        tapAnyway(app.buttons.matching(identifier: "site-card").firstMatch)
        // The site's page (1.2): the month, the group, Write today and Sheet.
        guard app.screen("screen-site").waitForExistence(timeout: 10) else {
            miss("site (the site did not open)")
            return
        }
        pause(1)
        capture("site", app)
        swipeUp(app)
        capture("site-lower", app)
        swipeDown(app, times: 3)

        tapAnyway(app.buttons.matching(identifier: "site-write-today").firstMatch)
        guard app.screen("screen-site-day").waitForExistence(timeout: 10) else {
            miss("site-day (Write today did not open the day)")
            return
        }
        pause(1)
        capture("site-day-top", app)
        siteDayScreens(app)
        extraWorkScreens(app)
        // Back to the site's page, where everything else the site has is.
        back(app)
        siteMenuScreens(app)

        // Archived: the second site put away, its page as an archived site
        // shows it, and the list with the Archived sites row underneath.
        back(app)
        let second = app.buttons.matching(identifier: "site-card").element(boundBy: 1)
        if tap(second, "the second site", app),
           tap(app.buttons.matching(identifier: "site-edit").firstMatch, "the site's settings", app) {
            let archived = app.switches["site-editor-archived"]
            if archived.waitForExistence(timeout: 5) {
                flip(archived)
                tap(app.buttons.matching(identifier: "site-editor-save").firstMatch, "Save the site", app)
                pause(1)
                capture("site-archived-day", app)
            } else {
                miss("site-archived-day (no Archived switch)")
                close(app, "site-editor-cancel")
            }
            back(app)
            pause(1)
            capture("sites-list-archived", app)
            let archivedRow = app.buttons.matching(identifier: "sites-archived").firstMatch
            if tap(archivedRow, "Archived sites", app) {
                pause(0.5)
                capture("sites-list-archived-open", app)
                back(app)
            }
        }
    }

    /// Today on the showcase site, from the top to the diary.
    private func siteDayScreens(_ app: XCUIApplication) {
        // The week strip opens out into the whole month, and back.
        if tap(app.buttons.matching(identifier: "site-month-toggle").firstMatch, "Show whole month", app) {
            pause(0.5)
            capture("site-day-month-grid", app)
            tap(app.buttons.matching(identifier: "site-month-toggle").firstMatch, "Show one week", app)
        }

        swipeUp(app)
        capture("site-day-crew", app)

        // A day not written yet: Same as usual writes it, so the rest of
        // the pictures see a written day.
        let usual = app.buttons.matching(identifier: "site-day-same-as-usual").firstMatch
        if usual.exists, tap(usual, "Same as usual", app) {
            pause(0.5)
            capture("site-day-written", app)
        }

        crewDayScreens(app)

        let times = app.descendants(matching: .any)["site-day-times"].firstMatch
        if tap(times, "the site's times", app) {
            capture("site-times", app)
            close(app, "site-hours-cancel")
        }

        siteMoveScreens(app)

        let weather = app.buttons.matching(identifier: "site-weather-menu").firstMatch
        if bringIntoView(weather, app), tap(weather, "Bad weather", app) {
            capture("site-rained-off-sheet", app)
            if tap(app.buttons.matching(identifier: "site-weather-stop-all").firstMatch, "No work today", app) {
                capture("site-rained-off-no-work", app)
            }
            close(app, "site-weather-stop-cancel")
        }

        let addExtraWork = app.buttons.matching(identifier: "extra-work-add").firstMatch
        if bringIntoView(addExtraWork, app) {
            capture("site-day-extra-work", app)
        } else {
            miss("site-day-extra-work (no extra work section)")
        }
        // The sample's finished jobs are not sent yet: "Send to boss (N)"
        // beside the Extra work heading.
        if bringIntoView(app.buttons.matching(identifier: "extra-work-send-report").firstMatch, app) {
            capture("site-day-send-to-boss", app)
        } else {
            miss("site-day-send-to-boss (no Send to boss button)")
        }

        let diary = app.buttons.matching(identifier: "site-day-diary").firstMatch
        if bringIntoView(diary, app), tap(diary, "Diary for this day", app) {
            pause(0.5)
            capture("site-day-diary", app)
            close(app, "site-diary-cancel")
        } else {
            miss("site-day-diary (no diary on the site day)")
        }
    }

    /// The crew's day from Change: the rows with their four buttons, one
    /// person's times, and why someone was away.
    private func crewDayScreens(_ app: XCUIApplication) {
        let change = app.buttons.matching(identifier: "site-day-change").firstMatch
        guard bringIntoView(change, app), tap(change, "Change", app) else {
            miss("site-crew-day (no Change on the day)")
            return
        }
        pause(0.5)
        capture("site-crew-day", app)
        let late = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'site-late-' AND identifier != 'site-late-you'"
        )).firstMatch
        if tap(late, "Late/early", app) {
            capture("site-person-times", app)
            close(app, "person-times-cancel")
        }
        let away = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'site-away-' AND identifier != 'site-away-you' AND identifier != 'site-away-cancel'"
        )).firstMatch
        if tap(away, "Away", app) {
            capture("site-absence-menu", app)
            close(app, "site-away-cancel")
        }
        close(app, "site-different-cancel")
    }

    /// The extra-work editor, new and existing, and the report to the boss.
    private func extraWorkScreens(_ app: XCUIApplication) {
        let editor = app.screen("screen-extra-work-editor")
        let addExtraWork = app.buttons.matching(identifier: "extra-work-add").firstMatch
        if bringIntoView(addExtraWork, app) {
            tapAnyway(addExtraWork)
            if editor.waitForExistence(timeout: 10) {
                pause(0.5)
                capture("extra-work-new", app)
                if tap(app.buttons.matching(identifier: "extra-work-hours-toggle").firstMatch, "How long it took", app) {
                    pause(0.5)
                }
                swipeDown(app, times: 3)
                capture("extra-work-new-open", app)
                swipeUp(app)
                capture("extra-work-new-open-lower", app)

                if tap(app.buttons.matching(identifier: "extra-work-new-item").firstMatch, "New item", app) {
                    capture("extra-work-new-item", app)
                    close(app, "extra-work-item-cancel")
                }
                if tap(app.buttons.matching(identifier: "extra-work-sign").firstMatch, "the client's signature", app) {
                    capture("extra-work-client-signature", app)
                    close(app, "extra-work-signature-cancel")
                }
                if tap(app.buttons.matching(identifier: "extra-work-edit-items").firstMatch, "the item list", app) {
                    capture("extra-work-catalogue", app)
                    if tap(app.buttons.matching(identifier: "extra-work-catalog-item").firstMatch, "an item in the list", app) {
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
            let job = app.buttons.matching(identifier: "extra-work-job-\(index)").firstMatch
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

        // The report is on the site's page (1.2); back to the day after.
        back(app)
        defer { tapAnyway(app.buttons.matching(identifier: "site-write-today").firstMatch) }
        if tap(app.buttons.matching(identifier: "site-extra-work-report").firstMatch, "the report to the boss", app),
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
                if tap(app.buttons.matching(identifier: "extra-work-report-sign").firstMatch, "the report's signature", app) {
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

    /// Everything behind the site's page (1.2): crew (and from it the
    /// sign-off and a person's month), diary, the sign-off row, the sheet's
    /// export, and the settings.
    private func siteMenuScreens(_ app: XCUIApplication) {
        swipeDown(app, times: 8)
        capture("site-buttons", app)
        do {
            if tap(app.buttons.matching(identifier: "site-crew").firstMatch, "the crew", app),
               app.screen("screen-crew").waitForExistence(timeout: 10) {
                pause(0.5)
                capture("crew", app)
                let member = app.descendants(matching: .any)["crew-member"].firstMatch
                if member.waitForExistence(timeout: 5) {
                    member.press(forDuration: 1.2)
                    pause(1)
                    capture("crew-member-menu", app)
                    if tap(app.buttons.matching(identifier: "crew-rename").firstMatch, "Rename", app) {
                        pause(0.5)
                        capture("crew-member-rename", app)
                        let cancel = app.buttons.matching(identifier: "crew-rename-cancel").firstMatch
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
                // A person's month and own sheet, from their row (1.2).
                if tap(app.buttons.matching(identifier: "crew-member").firstMatch, "a person's month", app) {
                    let share = app.buttons.matching(identifier: "crew-sheet-share").firstMatch
                    if !(share.waitForExistence(timeout: 8) && share.isEnabled) {
                        // This month may have nothing yet; the sample has last month.
                        tapAnyway(app.buttons.matching(identifier: "period-previous").firstMatch)
                        pause(1.5)
                    }
                    pause(1)
                    capture("crew-member-sheet", app)
                    swipeUp(app)
                    capture("crew-member-sheet-lower", app)
                    if tap(app.buttons.matching(identifier: "crew-sheet-sign").firstMatch, "Sign the month", app) {
                        pause(0.5)
                        capture("crew-member-sign", app)
                        close(app, "signature-cancel")
                    }
                    back(app)
                }
                if tap(app.buttons.matching(identifier: "crew-add-from-sites").firstMatch, "Add from other sites", app) {
                    capture("crew-add-from-other-sites", app)
                    close(app, "crew-picker-cancel")
                }
                signOffScreens(app)
                back(app)
            }
        }

        if tap(app.buttons.matching(identifier: "site-diary-list").firstMatch, "the site diary", app) {
            pause(1)
            capture("site-diary-list", app)
            close(app, "site-diary-list-done")
        }

        if tap(app.buttons.matching(identifier: "site-overview-sign-off").firstMatch, "the Sign-off row", app) {
            pause(1)
            capture("site-overview-sign-off", app)
            close(app, "sign-off-done")
        }

        if tap(app.buttons.matching(identifier: "site-export").firstMatch, "the site's Sheet", app),
           app.screen("screen-site-export").waitForExistence(timeout: 10) {
            exportScreens(app, prefix: "site-export")
            // One sheet per person, in This sheet: the switch, and the first
            // person's page back on the export screen.
            if tap(app.buttons.matching(identifier: "export-this-sheet").firstMatch, "This sheet", app) {
                let perPerson = app.switches.matching(identifier: "export-per-person").firstMatch
                if perPerson.waitForExistence(timeout: 5) {
                    flip(perPerson)
                    pause(1)
                    capture("site-export-per-person", app)
                    back(app)
                    pause(1.5)
                    capture("site-export-per-person-preview", app)
                    if tap(app.buttons.matching(identifier: "export-this-sheet").firstMatch, "This sheet", app),
                       perPerson.waitForExistence(timeout: 5) {
                        flip(perPerson)
                    }
                } else {
                    miss("site-export-per-person (no switch)")
                }
                back(app)
            }
            // Which sites (1.2): the chips, a second site ticked, and the one
            // sheet for both.
            swipeDown(app, times: 2)
            capture("site-export-sheet-sites", app)
            if tap(app.buttons.matching(identifier: "export-sheet-site-0").firstMatch, "a second site", app) {
                pause(1.5)
                capture("site-export-sheet-sites-chosen", app)
                capture("site-export-combined", app)
            }
            close(app, "export-done")
        }

        if tap(app.buttons.matching(identifier: "site-edit").firstMatch, "the site's settings", app) {
            capture("site-edit", app)
            swipeUp(app)
            capture("site-edit-usual-day", app)
            if tap(app.buttons.matching(identifier: "site-editor-work-days").firstMatch, "Work days", app) {
                capture("site-edit-work-days", app)
                back(app)
            }
            swipeDown(app, times: 3)
            arrivalReminderScreens(app)
            close(app, "site-editor-cancel")
        }
    }

    /// Crew sign-off, from the crew's toolbar (1.2): a sheet with the month,
    /// each person, and the line they sign on.
    private func signOffScreens(_ app: XCUIApplication) {
        if tap(app.buttons.matching(identifier: "site-sign-off").firstMatch, "Crew sign-off", app) {
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
            } else {
                miss("site-sign-off (the sign-off did not open)")
            }
            close(app, "sign-off-done")
        }
    }

    /// The new-site wizard (1.2), every step, from "Copy from a site", then
    /// "Several sites at once" with names typed in. Cancelled each time, so
    /// the sample's sites stay as they are.
    private func newSiteWizardScreens(_ app: XCUIApplication) {
        guard tap(app.buttons.matching(identifier: "sites-add").firstMatch, "New site", app) else { return }
        capture("wizard-1-start", app)
        if tap(app.buttons.matching(identifier: "wizard-start-copy").firstMatch, "Copy from a site", app) {
            capture("wizard-1-copy", app)
        }
        if tap(app.buttons.matching(identifier: "wizard-next").firstMatch, "Next to the place", app) {
            let name = app.textFields["site-name"].firstMatch
            if name.waitForExistence(timeout: 5) {
                name.tap()
                name.typeText("Trg Pravde")
            }
            capture("wizard-2-where", app)
        }
        let steps = ["wizard-3-crew", "wizard-4-usual-day", "wizard-5-extras", "wizard-6-check"]
        for step in steps {
            guard tap(app.buttons.matching(identifier: "wizard-next").firstMatch, "Next to \(step)", app) else { break }
            capture(step, app)
        }
        close(app, "wizard-cancel")

        guard tap(app.buttons.matching(identifier: "sites-add").firstMatch, "New site again", app) else { return }
        if tap(app.buttons.matching(identifier: "wizard-start-several").firstMatch, "Several sites at once", app),
           tap(app.buttons.matching(identifier: "wizard-next").firstMatch, "Next to the names", app) {
            let names = app.descendants(matching: .any).matching(identifier: "wizard-several-names").firstMatch
            if names.waitForExistence(timeout: 5) {
                names.tap()
                names.typeText("Solarka\nVukovarska 5\nJarun")
            }
            capture("wizard-2-several", app)
            for _ in 0..<4 {
                tap(app.buttons.matching(identifier: "wizard-next").firstMatch, "Next", app)
            }
            capture("wizard-6-several-check", app)
        }
        close(app, "wizard-cancel")
    }

    /// The arrival reminder in the site's settings (1.2): the explanation
    /// before anything is asked, then the saved place with its map. The
    /// location is the UI tests' fake, so no permission prompt appears; the
    /// editor is cancelled afterwards, so nothing is kept.
    private func arrivalReminderScreens(_ app: XCUIApplication) {
        // Its own page (1.2), from the site's settings.
        let row = app.buttons.matching(identifier: "site-editor-arrival-row").firstMatch
        guard bringIntoView(row, app) else {
            miss("site-arrival-explanation (no Arrival reminder row)")
            return
        }
        tapAnyway(row)
        defer { back(app) }
        let arrival = app.switches["site-editor-arrival"].firstMatch
        guard arrival.waitForExistence(timeout: 5) else {
            miss("site-arrival-explanation (no arrival switch)")
            return
        }
        flip(arrival)
        guard app.staticTexts["site-arrival-explanation"].firstMatch.waitForExistence(timeout: 5) else {
            miss("site-arrival-explanation (the explanation did not open)")
            return
        }
        capture("site-arrival-explanation", app)
        tapAnyway(app.buttons.matching(identifier: "site-arrival-continue").firstMatch)
        let coordinates = app.descendants(matching: .any)["site-arrival-coordinates"].firstMatch
        if coordinates.waitForExistence(timeout: 5) {
            _ = bringIntoView(app.descendants(matching: .any)["site-arrival-map"].firstMatch, app)
            capture("site-edit-arrival-place", app)
            // The address is in the site's settings, one back.
            back(app)
            siteAddressScreen(app)
            // Forward again, for the deferred back.
            tapAnyway(row)
        } else {
            miss("site-edit-arrival-place (no place was saved)")
        }
    }

    /// The site's address (1.2), filled in from the place just saved: the
    /// fake's answer, so nothing is asked of Apple Maps.
    private func siteAddressScreen(_ app: XCUIApplication) {
        let fill = app.buttons.matching(identifier: "site-address-fill").firstMatch
        guard bringIntoView(fill, app) else {
            miss("site-edit-address (no Fill in from the saved place)")
            return
        }
        tapAnyway(fill)
        let address = app.textViews["site-address"].firstMatch.exists
            ? app.textViews["site-address"].firstMatch
            : app.textFields["site-address"].firstMatch
        _ = bringIntoView(address, app)
        capture("site-edit-address", app)
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

        // Check your payslip: the figures, then how they compare.
        let payslip = app.buttons.matching(identifier: "insights-payslip-check").firstMatch
        if bringIntoView(payslip, app) {
            tapAnyway(payslip)
            let overtime = app.textFields.matching(identifier: "payslip-field-overtime").firstMatch
            if overtime.waitForExistence(timeout: 5) {
                capture("payslip-check-entry", app)
                tapAnyway(overtime)
                overtime.typeText("12")
                if tap(app.buttons.matching(identifier: "payslip-check").firstMatch, "the payslip's Check button", app) {
                    capture("payslip-check-result", app)
                }
                close(app, "payslip-done")
            } else {
                miss("payslip-check-entry (did not open)")
                close(app, "payslip-cancel")
            }
        } else {
            miss("payslip-check (no row on the month)")
        }
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

        let review = app.buttons.matching(identifier: "insights-year-review").firstMatch
        if bringIntoView(review, app) {
            tapAnyway(review)
            if app.buttons.matching(identifier: "year-review-close").firstMatch.waitForExistence(timeout: 10) {
                pause(1.5)
                capture("year-in-review", app)
                swipeUp(app)
                pause(0.5)
                capture("year-in-review-lower", app)
                app.buttons.matching(identifier: "year-review-close").firstMatch.tap()
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
        let last = app.buttons.matching(identifier: "settings-feedback").firstMatch
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
            // Allowance & travel, under Pay (1.2), off as shipped, then
            // switched on: the rates and travel. Left on, for
            // `allowanceScreens` after Settings.
            self.settingsPage("settings-allowance", "settings-allowance", app) {
                let enabled = app.switches["allowance-enabled"].firstMatch
                if enabled.waitForExistence(timeout: 5) {
                    self.flip(enabled)
                    self.pause(0.5)
                    self.capture("settings-allowance-on", app)
                } else {
                    self.miss("settings-allowance-on (no switch)")
                }
            }
        }
        settingsPage("settings-new-sites", "settings-new-sites", app) {
            self.swipeUp(app)
            self.capture("settings-new-sites-lower", app)
        }
        settingsPage("settings-jobs", "settings-jobs", app) {
            if self.tap(app.buttons.matching(identifier: "jobs-row").firstMatch, "a job", app) {
                self.capture("settings-job-editor", app)
                self.close(app, "job-editor-cancel")
            }
            if self.tap(app.buttons.matching(identifier: "jobs-add").firstMatch, "Add a job", app) {
                self.capture("settings-job-new", app)
                self.close(app, "job-editor-cancel")
            }
        }
        settingsPage("settings-calculation", "settings-calculation", app) {
            self.swipeUp(app)
            self.capture("settings-calculation-lower", app)
            // Closed months: their own screen now. Last month is closed
            // here, for the calendar's notice afterwards (see
            // `closedMonthScreens`), which reopens it.
            if self.tap(app.buttons.matching(identifier: "settings-closed-months").firstMatch, "Closed months", app) {
                self.capture("settings-closed-months", app)
                if self.tap(app.buttons.matching(identifier: "closed-months-close").firstMatch, "Close last month", app) {
                    self.capture("settings-closed-months-one", app)
                }
                self.back(app)
            }
        }
        settingsPage("settings-reminders", "settings-reminders", app) {
            self.swipeUp(app)
            self.capture("settings-reminders-lower", app)
        }
        settingsPage("settings-fields", "settings-fields", app)
        settingsPage("settings-day-types-holidays", "settings-day-types-holidays", app) {
            self.dayTypeAndHolidayScreens(app)
        }
        settingsPage("settings-calendar", "settings-calendar", app)
        settingsPage("settings-theme", "settings-theme", app)
        settingsPage("settings-export-options", "settings-export-options", app) {
            self.swipeUp(app)
            self.capture("settings-export-options-lower", app)
        }
        settingsPage("settings-icloud-backup", "settings-icloud-backup", app) {
            self.settingsPage("settings-icloud", "settings-icloud", app)
            self.settingsPage("settings-data", "settings-backup-and-data", app)
        }
        settingsPage("settings-privacy", "settings-privacy", app) {
            self.swipeUp(app)
            self.capture("settings-privacy-lower", app)
        }
        settingsPage("settings-help", "settings-help", app)
        settingsSearchScreens(app)
    }

    /// Searching Settings (1.2): a word the rows are known by.
    private func settingsSearchScreens(_ app: XCUIApplication) {
        swipeDown(app, times: 3)
        let search = app.searchFields.firstMatch
        guard search.waitForExistence(timeout: 5) else {
            miss("settings-search (no search field)")
            return
        }
        search.tap()
        search.typeText("overtime")
        pause(0.8)
        capture("settings-search", app)
        let cancel = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "Cancel", "Cancel")).firstMatch
        if cancel.exists { cancel.tap() } else { search.buttons.firstMatch.tap() }
        pause(0.5)
    }

    /// Settings › Day types & holidays: the two screens under it.
    private func dayTypeAndHolidayScreens(_ app: XCUIApplication) {
        settingsPage("settings-day-types", "settings-day-types", app) {
            if self.tap(app.buttons.matching(identifier: "day-types-row").firstMatch, "a day type", app) {
                self.capture("settings-day-type-editor", app)
                self.close(app, "day-type-editor-cancel")
            }
            // Sick, fifth in the list: Paid at, the 42 days and the note.
            let sick = app.buttons.matching(identifier: "day-types-row").element(boundBy: 4)
            if self.tap(sick, "the Sick day type", app) {
                self.capture("settings-day-type-sick", app)
                self.swipeUp(app)
                self.capture("settings-day-type-sick-lower", app)
                self.close(app, "day-type-editor-cancel")
            }
            if self.tap(app.buttons.matching(identifier: "day-types-add").firstMatch, "Add a day type", app) {
                self.capture("settings-day-type-new", app)
                self.close(app, "day-type-editor-cancel")
            }
        }
        settingsPage("settings-holidays", "settings-holidays", app) {
            if self.tap(app.buttons.matching(identifier: "holidays-row").firstMatch, "a holiday", app) {
                self.capture("settings-holiday-editor", app)
                self.close(app, "holiday-editor-cancel")
            }
            if self.tap(app.buttons.matching(identifier: "holidays-add").firstMatch, "Add a holiday", app) {
                self.capture("settings-holiday-new", app)
                self.close(app, "holiday-editor-cancel")
            }
            if self.tap(app.buttons.matching(identifier: "public-holidays-open").firstMatch, "Add public holidays", app) {
                self.publicHolidayPicker(app, prefix: "settings-public-holidays")
            }
        }
    }

    /// With the allowance switched on in Settings: today's editor with its
    /// allowance, kilometres and travel, then saved with the allowance, the
    /// month's summary line and Insights' lines; and the site day with its
    /// kilometres and a crew row's menu offering the allowance.
    private func allowanceScreens(_ app: XCUIApplication) {
        app.tab(.calendar).tap()
        pause(1)
        let save = app.openTodaysEditor()
        guard save.waitForExistence(timeout: 10) else {
            miss("day-editor-allowance (today's editor did not open)")
            return
        }
        tap(app.buttons.matching(identifier: "day-editor-more").firstMatch, "Allowance, km, note…", app)
        let allowance = app.switches["day-editor-allowance"].firstMatch
        if bringIntoView(allowance, app) {
            capture("day-editor-allowance", app)
            flip(allowance)
            close(app, "day-extras-done")
            tapAnyway(save)
            pause(1)
            back(app)
            swipeUp(app)
            swipeUp(app)
            capture("calendar-month-summary-allowance", app)
            swipeDown(app, times: 4)
        } else {
            miss("day-editor-allowance (no allowance section)")
            close(app, "day-extras-done")
            close(app, "day-editor-cancel")
        }

        app.tab(.insights).tap()
        pause(1)
        if bringIntoView(app.descendants(matching: .any)["insights-allowance"].firstMatch, app) {
            capture("insights-allowance", app)
        } else {
            miss("insights-allowance (no allowance line)")
        }
        swipeDown(app, times: 3)

        app.tab(.sites).tap()
        if tap(app.buttons.matching(identifier: "site-card").firstMatch, "the site", app),
           tap(app.buttons.matching(identifier: "site-write-today").firstMatch, "Write today", app),
           app.screen("screen-site-day").waitForExistence(timeout: 10) {
            if bringIntoView(app.textFields["site-day-kilometres"].firstMatch, app) {
                capture("site-day-kilometres", app)
            } else {
                miss("site-day-kilometres (no kilometres row)")
            }
            let allowance = app.buttons.matching(identifier: "site-day-allowance").firstMatch
            if bringIntoView(allowance, app), tap(allowance, "Field allowance", app) {
                if app.buttons["site-allowance-done"].firstMatch.waitForExistence(timeout: 5) {
                    capture("site-person-allowance-menu", app)
                    close(app, "site-allowance-done")
                } else {
                    miss("site-person-allowance-menu (no allowance sheet)")
                }
            }
            back(app)
            back(app)
        }
    }

    /// "Moved to another site…" (1.2): the sheet, the day after the move with
    /// its banner and the movers' rows, your calendar day on two sites, and
    /// the export's Sites picker for the month. Undone at the end, so nothing
    /// after this sees the move.
    private func siteMoveScreens(_ app: XCUIApplication) {
        let move = app.buttons.matching(identifier: "site-day-move").firstMatch
        guard bringIntoView(move, app), tap(move, "Moved to another site", app) else { return }
        pause(0.8)
        capture("site-move-sheet", app)
        guard tap(app.buttons.matching(identifier: "site-move-to-0").firstMatch, "the other site", app) else {
            close(app, "site-move-cancel")
            return
        }
        capture("site-move-sheet-chosen", app)
        guard tap(app.buttons.matching(identifier: "site-move-confirm").firstMatch, "Move", app) else {
            close(app, "site-move-cancel")
            return
        }
        pause(1)
        bringIntoView(app.descendants(matching: .any)["site-move-banner"].firstMatch, app)
        capture("site-day-after-move", app)

        // Your own day, now on two sites.
        app.tab(.calendar).tap()
        pause(1)
        if tap(app.buttons.matching(identifier: "day-\(Self.todayKey)").firstMatch, "today in the calendar", app) {
            bringIntoView(app.descendants(matching: .any)["day-card-site-0"].firstMatch, app)
            capture("calendar-day-two-sites", app)
            back(app)
        }
        if tap(app.buttons.matching(identifier: "calendar-export").firstMatch, "Export", app) {
            if bringIntoView(app.descendants(matching: .any)["export-sites"].firstMatch, app) {
                capture("export-sites-option", app)
            } else {
                miss("export-sites-option (no Sites row)")
            }
            close(app, "export-done")
        }

        app.tab(.sites).tap()
        pause(1)
        if tap(app.buttons.matching(identifier: "site-move-undo").firstMatch, "Undo the move", app) {
            pause(1)
        }
        swipeDown(app, times: 2)
    }

    /// Last month, closed in Settings a moment ago: the calendar's notice,
    /// its menu offering Reopen, and the question Reopen asks. Reopened at
    /// the end, so nothing after this sees a closed month.
    private func closedMonthScreens(_ app: XCUIApplication) {
        app.tab(.calendar).tap()
        pause(1)
        guard tap(app.buttons.matching(identifier: "calendar-previous").firstMatch, "last month (closed)", app) else { return }
        pause(0.5)
        capture("calendar-closed-month", app)
        if tap(app.buttons.matching(identifier: "calendar-more").firstMatch, "the calendar's menu on a closed month", app) {
            capture("calendar-menu-closed-month", app)
            dismissMenu(app)
        }
        if tap(app.buttons.matching(identifier: "calendar-closed-reopen").firstMatch, "Reopen on the notice", app) {
            capture("calendar-reopen-confirm", app)
            tap(app.buttons.matching(identifier: "calendar-reopen-confirm").firstMatch, "Reopen", app)
        }
        tap(app.buttons.matching(identifier: "calendar-next").firstMatch, "back to this month", app)
    }

    /// The countries, a country's regions, and a set before it is added.
    /// Cancelled, so nothing is added.
    private func publicHolidayPicker(_ app: XCUIApplication, prefix: String) {
        let germany = app.buttons.matching(identifier: "public-holidays-country-de").firstMatch
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
        let austria = app.buttons.matching(identifier: "public-holidays-country-at").firstMatch
        if tap(austria, "Austria", app), app.buttons.matching(identifier: "public-holidays-add").firstMatch.waitForExistence(timeout: 5) {
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
        let row = app.buttons.matching(identifier: identifier).firstMatch
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
        if tap(app.buttons.matching(identifier: "settings-pro").firstMatch, "the Pro row", app) {
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
            if step == "crew", app.buttons.matching(identifier: "setup-crew-yes").firstMatch.exists {
                // A crew lead: the last step then offers to create a site.
                app.buttons.matching(identifier: "setup-crew-yes").firstMatch.tap()
                pause(0.5)
            }
            capture("setup-\(index + 1)-\(step)", app)
            guard step != "finish" else { break }
            let next = app.buttons.matching(identifier: "setup-continue").firstMatch
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
            let next = app.buttons.matching(identifier: "tour-next").firstMatch
            let done = app.buttons.matching(identifier: "tour-done").firstMatch
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
                let review = app.buttons.matching(identifier: "insights-year-review").firstMatch
                if bringIntoView(review, app) {
                    tapAnyway(review)
                    if app.buttons.matching(identifier: "year-review-close").firstMatch.waitForExistence(timeout: 10) {
                        pause(1)
                        capture("empty-year-in-review", app)
                        app.buttons.matching(identifier: "year-review-close").firstMatch.tap()
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
        if tap(siteApp.buttons.matching(identifier: "site-card").firstMatch, "the sample site", siteApp),
           tap(siteApp.buttons.matching(identifier: "site-write-today").firstMatch, "Write today", siteApp),
           siteApp.screen("screen-site-day").waitForExistence(timeout: 10) {
            pause(1)
            capture("empty-site-day-unwritten", siteApp)
            if bringIntoView(siteApp.buttons.matching(identifier: "extra-work-add").firstMatch, siteApp) {
                capture("empty-site-day-extra-work", siteApp)
            }
            // The report is on the site's page (1.2).
            back(siteApp)
            if tap(siteApp.buttons.matching(identifier: "site-extra-work-report").firstMatch, "the empty report", siteApp),
               siteApp.screen("screen-extra-work-report").waitForExistence(timeout: 10) {
                pause(1)
                capture("empty-extra-work-report", siteApp)
                close(siteApp, "extra-work-report-done")
            }
            tap(siteApp.buttons.matching(identifier: "site-write-today").firstMatch, "Write today again", siteApp)
            heldBackReport(siteApp)
        } else {
            miss("empty-site-day-unwritten (the site did not open)")
        }
        siteApp.terminate()
    }

    /// A job written and left in progress, as new jobs are: the report is
    /// empty only because of it, and says so, with Include them and Mark
    /// finished…; then a photo on the job, large, if the simulator's
    /// library gives one.
    private func heldBackReport(_ app: XCUIApplication) {
        let editor = app.screen("screen-extra-work-editor")
        guard bringIntoView(app.buttons.matching(identifier: "extra-work-add").firstMatch, app) else {
            miss("extra-work-report-held-back (no Add extra work)")
            return
        }
        tapAnyway(app.buttons.matching(identifier: "extra-work-add").firstMatch)
        guard editor.waitForExistence(timeout: 10) else {
            miss("extra-work-report-held-back (the editor did not open)")
            return
        }
        let description = app.descendants(matching: .any)["extra-work-description"].firstMatch
        if description.waitForExistence(timeout: 5) {
            tapAnyway(description)
            description.typeText("Core hole for the drain")
        }
        photoViewer(app)
        close(app, "extra-work-save")

        // The report is on the site's page (1.2), one back from the day.
        back(app)
        if tap(app.buttons.matching(identifier: "site-extra-work-report").firstMatch, "the report held back", app),
           app.screen("screen-extra-work-report").waitForExistence(timeout: 10) {
            pause(1)
            if app.descendants(matching: .any)["extra-work-report-held-back"].waitForExistence(timeout: 5) {
                capture("extra-work-report-held-back", app)
            } else {
                miss("extra-work-report-held-back (no held-back state)")
            }
            if tap(app.buttons.matching(identifier: "extra-work-report-mark-finished").firstMatch, "Mark finished…", app) {
                pause(0.5)
                capture("extra-work-report-mark-finished", app)
            }
            close(app, "extra-work-report-done")
        }
    }

    /// The photo viewer, from the extra-work editor's photos. The photo comes
    /// from the system picker, which belongs to the simulator, so a picker
    /// that cannot be driven is noted rather than failed.
    private func photoViewer(_ app: XCUIApplication) {
        let add = app.buttons.matching(identifier: "extra-work-add-photos").firstMatch
        guard bringIntoView(add, app) else {
            optional.append("photo-viewer (no Add photos)")
            return
        }
        tapAnyway(add)
        pause(2)
        // The picker's grid, bridged into the app's tree as XCTest sees it.
        let picked = app.scrollViews.otherElements.images.firstMatch
        if picked.waitForExistence(timeout: 8) {
            tapAnyway(picked)
            pause(1)
            // Several photos may be picked, so the picker waits for its own
            // Add, the last button on its bar (labels differ per language).
            let bars = app.navigationBars
            if bars.count > 0 {
                let buttons = bars.element(boundBy: bars.count - 1).buttons
                if buttons.count > 1 { tapAnyway(buttons.element(boundBy: buttons.count - 1)) }
            }
            pause(1.5)
        }
        let save = app.buttons.matching(identifier: "extra-work-save").firstMatch
        if !save.isHittable {
            // The picker is still up: swipe it away, back to the editor.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            pause(1)
        }
        let photo = app.buttons.matching(identifier: "extra-work-photo").firstMatch
        guard photo.waitForExistence(timeout: 3), bringIntoView(photo, app) else {
            optional.append("photo-viewer (the system picker gave no photo)")
            return
        }
        tapAnyway(photo)
        if app.buttons.matching(identifier: "photo-viewer-done").firstMatch.waitForExistence(timeout: 5) {
            pause(0.5)
            capture("photo-viewer", app)
            close(app, "photo-viewer-done")
        } else {
            optional.append("photo-viewer (did not open)")
        }
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
        guard toggle.exists else { return }
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
        let button = app.buttons.matching(identifier: identifier).firstMatch
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
