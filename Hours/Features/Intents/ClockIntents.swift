import AppIntents
import Foundation

/// Starting the clock from Siri, Shortcuts or Spotlight.
struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "Clock in"
    static var description = IntentDescription(
        "Starts the clock. Does nothing if one is already running."
    )
    /// Deliberately runs without opening the app: the whole point is that
    /// starting work costs one phrase and no screen.
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let clock = HoursStack.timeClock
        let formatting = HoursStack.settings.dateFormatting

        if let already = clock.running {
            return .result(dialog: IntentDialog(
                "You were already clocked in at \(formatting.time(already.start, on: already.date))."
            ))
        }

        guard let started = clock.clockIn() else {
            return .result(dialog: IntentDialog("The clock could not be started."))
        }
        HoursStack.refreshWidget()
        return .result(dialog: IntentDialog(
            "Clocked in at \(formatting.time(started.start, on: started.date))."
        ))
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
        let clock = HoursStack.timeClock
        let duration = HoursStack.settings.settings.displayFormatting

        switch clock.clockOut() {
        case .nothingRunning:
            return .result(dialog: IntentDialog("You are not clocked in."))
        case let .recorded(date, workedMinutes, wasCapped):
            HoursStack.refreshWidget()
            let formatting = HoursStack.settings.dateFormatting
            if wasCapped {
                return .result(dialog: IntentDialog(
                    "Clocked out. That shift had been running over a day, so \(formatting.mediumDate(date)) was capped — worth checking."
                ))
            }
            return .result(dialog: IntentDialog(
                "Clocked out. \(duration.string(workedMinutes)) recorded for \(formatting.mediumDate(date))."
            ))
        }
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
        let duration = settings.displayFormatting
        let calendar = HoursStack.calendar
        let today = CalendarDate.today(in: calendar)

        var sentences: [String] = []

        if let running = HoursStack.clock.running {
            let minutes = running.elapsedMinutes(at: Date())
            sentences.append("You have been clocked in for \(duration.string(minutes)).")
        }

        let range = today.yearMonth.range(in: calendar)
        let repository = HoursStack.repository
        let summary = HoursStack.engine.summary(
            in: range,
            records: repository.records(in: range),
            holidays: repository.holidayRules(),
            countingThrough: today
        )

        sentences.append("This month you have worked \(duration.string(summary.workedMinutes)).")

        if settings.features.showsBalance {
            let balance = summary.balanceMinutes
            if balance == 0 {
                sentences.append("You are exactly on target.")
            } else if balance > 0 {
                sentences.append("You are \(duration.string(balance)) ahead.")
            } else {
                sentences.append("You are \(duration.string(-balance)) behind.")
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
