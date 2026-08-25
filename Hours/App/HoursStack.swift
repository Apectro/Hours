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
    private static let opened: (container: ModelContainer, failure: String?, isSyncing: Bool) = {
        let wantsSync = SyncPreference.isEnabled

        if wantsSync {
            do {
                return (try HoursModelContainer.make(syncsWithICloud: true), nil, true)
            } catch {
                // Almost always the iCloud capability not being enabled in the
                // build, or no iCloud account on the device. Falling back to
                // the local store is right either way: the hours are on this
                // device and readable, they are simply not being sent anywhere.
                if let local = try? HoursModelContainer.make(syncsWithICloud: false) {
                    return (
                        local,
                        "iCloud sync could not be started, so this device is using its own copy. Everything you enter is still saved here.",
                        false
                    )
                }
            }
        } else {
            if let local = try? HoursModelContainer.make(syncsWithICloud: false) {
                return (local, nil, false)
            }
        }

        // Never refuse to start. A temporary store keeps the app usable and the
        // banner says so, which beats a blank screen over data nobody can reach.
        return (
            HoursModelContainer.ephemeral(),
            "Your data could not be opened, so this session is temporary. Nothing you enter now will be saved.",
            false
        )
    }()

    static var container: ModelContainer { opened.container }
    static var storeFailure: String? { opened.failure }

    /// Whether this session actually opened a syncing store — which is not the
    /// same as the preference being on, since the store may have refused.
    static var isSyncing: Bool { opened.isSyncing }

    /// Settings live in `UserDefaults`, not in the SwiftData store, so they
    /// need their own way across. The key-value store is only reached once
    /// a syncing container has opened, which is the proof that this build
    /// actually carries the iCloud entitlement.
    static let settings = SettingsStore(
        shared: isSyncing ? NSUbiquitousKeyValueStore.default : nil
    )
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
