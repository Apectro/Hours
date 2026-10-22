import AppIntents
import Foundation

/// Starting the clock from Siri, Shortcuts or Spotlight.
///
/// A `LiveActivityIntent` rather than a plain one because it runs without
/// opening the app, and only an intent marked this way may start a Live
/// Activity from the background. Without it the lock screen would show the
/// clock when it was started in the app and not when it was started by voice.
struct ClockInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock in"
    static var description = IntentDescription(
        "Starts the clock. Does nothing if one is already running."
    )
    /// Deliberately runs without opening the app: the whole point is that
    /// starting work costs one phrase and no screen.
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Self.clockIn()))
    }

    /// Starts the clock and says what happened. Shared with Clock in or out.
    @MainActor
    static func clockIn() -> String {
        let clock = HoursStack.timeClock
        let formatting = HoursStack.settings.dateFormatting

        if let already = clock.running {
            return String(
                localized: "You were already clocked in at \(formatting.time(already.start, on: already.date)).",
                comment: "Siri, asked to clock in when the clock was already running"
            )
        }

        guard let started = clock.clockIn() else {
            return String(
                localized: "The clock could not be started.",
                comment: "Siri, when clocking in failed"
            )
        }
        HoursStack.refreshWidget()
        return String(
            localized: "Clocked in at \(formatting.time(started.start, on: started.date)).",
            comment: "Siri, confirming the clock started"
        )
    }
}

/// Stopping the clock and recording the block.
struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock out"
    static var description = IntentDescription(
        "Stops the clock and records the hours against the day the shift started."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: Self.clockOut()))
    }

    /// Stops the clock and says what was recorded. Shared with Clock in or out.
    @MainActor
    static func clockOut() -> String {
        let clock = HoursStack.timeClock

        switch clock.clockOut() {
        case .nothingRunning:
            return String(
                localized: "You are not clocked in.",
                comment: "Siri, asked to clock out with no clock running"
            )
        case let .monthIsClosed(month):
            // The shift is gone either way — the clock has already stopped —
            // so name the month rather than saying only that it failed. The
            // widget and the Live Activity still have to hear that it stopped.
            HoursStack.refreshWidget()
            let formatting = HoursStack.settings.dateFormatting
            return String(
                localized: "\(formatting.monthTitle(month)) is closed, so that shift was not recorded.",
                comment: "Siri, clocking out into a month that refuses edits"
            )
        case let .recorded(date, workedMinutes, wasCapped):
            HoursStack.refreshWidget()
            let formatting = HoursStack.settings.dateFormatting
            if wasCapped {
                return String(
                    localized: "Clocked out. That shift had been running over a day, so \(formatting.fullDate(date)) was capped — worth checking.",
                    comment: "Siri, when a forgotten clock ran past a full day"
                )
            }
            return String(
                localized: "Clocked out. \(SpokenDuration.string(workedMinutes)) recorded for \(formatting.fullDate(date)).",
                comment: "Siri, confirming the clock stopped and what it recorded"
            )
        }
    }
}

/// One button for both: the Action Button can run a single shortcut, and
/// the person pressing it knows whether they are arriving or leaving
/// without having to choose which shortcut to set up.
struct ClockInOrOutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock in or out"
    static var description = IntentDescription(
        "Starts the clock, or stops it and records the hours if it is running."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = HoursStack.clock.running == nil ? ClockInIntent.clockIn() : ClockOutIntent.clockOut()
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Today on the site card's site, filled from its last written day: the
/// Same as yesterday control, for Shortcuts and the Action Button.
///
/// Opens the app, because what it does happens on the site screen — which
/// still declines a day that is written or a month that is closed. The link
/// is left where a tapped notification leaves one, and the root follows it.
struct SameAsYesterdayIntent: AppIntent {
    static var title: LocalizedStringResource = "Same as yesterday"
    static var description = IntentDescription(
        "Opens today on your site, filled in like the last day."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HoursStack.notificationLinks.pending = AppLink.sameAsYesterday(from: HoursStack.widgetWriter.snapshot())
        return .result()
    }
}

/// Today's day editor: the Write today control, for Shortcuts and the
/// Action Button.
struct WriteTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Write today"
    static var description = IntentDescription("Opens today's day to write it.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        HoursStack.notificationLinks.pending = .writeToday
        return .result()
    }
}

/// Asking where things stand without opening anything.
struct HoursStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check my hours"
    static var description = IntentDescription(
        "Says whether the clock is running and how this month's balance stands."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = HoursStack.settings.settings
        let calendar = HoursStack.calendar
        let today = CalendarDate.today(in: calendar)

        var sentences: [String] = []

        if let running = HoursStack.clock.running {
            let minutes = running.elapsedMinutes(at: Date())
            sentences.append(String(
                localized: "You have been clocked in for \(SpokenDuration.string(minutes)).",
                comment: "Siri status, while the clock is running"
            ))
        }

        let range = today.yearMonth.range(in: calendar)
        let repository = HoursStack.repository
        let summary = HoursStack.engine.summary(
            in: range,
            records: repository.records(in: range),
            holidays: repository.holidayRules(),
            countingThrough: today
        )

        sentences.append(String(
            localized: "This month you have worked \(SpokenDuration.string(summary.workedMinutes)).",
            comment: "Siri status, the month's total"
        ))

        if settings.features.showsBalance {
            let balance = summary.balanceMinutes
            if balance == 0 {
                sentences.append(String(
                    localized: "You are exactly on target.",
                    comment: "Siri status, a balance of exactly zero"
                ))
            } else if balance > 0 {
                sentences.append(String(
                    localized: "You are \(SpokenDuration.string(balance)) ahead.",
                    comment: "Siri status, a balance in credit"
                ))
            } else {
                sentences.append(String(
                    localized: "You are \(SpokenDuration.string(-balance)) behind.",
                    comment: "Siri status, a balance in deficit"
                ))
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: sentences.joined(separator: " ")))
    }
}

/// The phrases that work without the user building a shortcut first.
struct HoursShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Start work in \(.applicationName)"
            ],
            shortTitle: "Clock in",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out with \(.applicationName)",
                "Finish work in \(.applicationName)"
            ],
            shortTitle: "Clock out",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ClockInOrOutIntent(),
            phrases: [
                "Clock in or out with \(.applicationName)"
            ],
            shortTitle: "Clock in or out",
            systemImageName: "playpause.circle"
        )
        AppShortcut(
            intent: SameAsYesterdayIntent(),
            phrases: [
                "Same as yesterday in \(.applicationName)"
            ],
            shortTitle: "Same as yesterday",
            systemImageName: "arrow.uturn.backward.circle"
        )
        AppShortcut(
            intent: WriteTodayIntent(),
            phrases: [
                "Write today in \(.applicationName)"
            ],
            shortTitle: "Write today",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: HoursStatusIntent(),
            phrases: [
                "Check my hours in \(.applicationName)",
                "How am I doing in \(.applicationName)"
            ],
            shortTitle: "Check hours",
            systemImageName: "chart.bar"
        )
    }
}
