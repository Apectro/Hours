import Foundation
import SwiftData

/// The app's single set of long-lived objects.
///
/// Exists because the app is no longer the only thing that reaches the store:
/// Shortcuts, Siri and the widget all need the same container, the same
/// settings and the same clock. Opening a second container on the same file
/// would be two caches of the same rows disagreeing with each other.
@MainActor
enum HoursStack {
    /// Built once, on first use.
    private static let opened: (container: ModelContainer, failure: String?) = {
        do {
            return (try HoursModelContainer.make(), nil)
        } catch {
            // Never refuse to start. A temporary store keeps the app usable and
            // the banner says so, which beats a blank screen over data nobody
            // can reach.
            return (
                HoursModelContainer.ephemeral(),
                "Your data could not be opened, so this session is temporary. Nothing you enter now will be saved."
            )
        }
    }()

    static var container: ModelContainer { opened.container }
    static var storeFailure: String? { opened.failure }

    static let settings = SettingsStore()
    static let clock = ActiveShiftStore()

    static var calendar: Calendar { settings.workCalendar }

    /// A repository on the main context. Intents and the app share it, so a
    /// change made by one is visible to the other immediately.
    static var repository: WorkdayRepository {
        WorkdayRepository(context: container.mainContext)
    }

    static var timeClock: TimeClock {
        TimeClock(
            repository: repository,
            clock: clock,
            settings: settings.settings,
            calendar: calendar
        )
    }

    static var engine: PeriodEngine {
        PeriodEngine(settings: settings.settings, calendar: calendar)
    }
}
