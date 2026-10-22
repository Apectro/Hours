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
    /// Set by the UI test target, which needs an app that starts from nothing
    /// and cannot touch whatever is really on the device. It is read from the
    /// launch arguments rather than compiled in behind `#if DEBUG`, because the
    /// build under test is the one that ships.
    static let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-hours-ui-testing")

    /// Built once, on first use.
    ///
    /// Which store opens is decided by `SyncLaunch.plan`, in the engine, so
    /// that no build can crash at launch because of sync: one not signed for
    /// iCloud never opens the syncing store, a launch that died opening it is
    /// not repeated, and a store that throws falls back to this device's own.
    /// This only carries the plan out.
    private static let opened: (container: ModelContainer, failure: String?, isSyncing: Bool) = {
        #if DEBUG || CLOUDKIT_SCHEMA_TOOLS
        // Before the real stack, on a scratch store: see `CloudKitSchema`.
        if !isRunningUITests, CloudKitSchema.isRequested {
            CloudKitSchema.initialize()
        }
        #endif
        let plan = SyncLaunch.plan(
            isUITesting: isRunningUITests,
            wantsSync: SyncPreference.isEnabled,
            isCompiledIn: SyncPreference.isCompiledIn,
            // Not even read in a UI test run, which never syncs.
            entitlement: isRunningUITests ? .missing : SyncPreference.entitlement,
            wasOpeningICloudStoreLastLaunch: !isRunningUITests && SyncLaunchMark.isSet
        )
        return open(following: plan)
    }()

    private static func open(following plan: SyncLaunchPlan) -> (container: ModelContainer, failure: String?, isSyncing: Bool) {
        if !isRunningUITests {
            // Set before the iCloud store is opened and cleared once it has
            // proven itself (`SyncMonitor`); any other plan clears a stale one.
            if plan.marksOpening { SyncLaunchMark.set() } else { SyncLaunchMark.clear() }
            if plan.switchesSyncOff { SyncPreference.isEnabled = false }
            if let problem = plan.problem { SyncPreference.problem = problem }
        }
        // Said once, on the launch that stopped sync; Settings › iCloud keeps
        // saying why until it is turned on again.
        let stopped = plan.problem.map { _ in
            String(localized: "iCloud sync could not be started, so this device is using its own copy. Everything you enter is still saved here.")
        }

        switch plan.store {
        case .temporary:
            return (HoursModelContainer.ephemeral(), nil, false)

        case .iCloud:
            do {
                return (try HoursModelContainer.make(syncsWithICloud: true), nil, true)
            } catch {
                // The hours are the same file either way: they are on this
                // device and readable, simply not being sent anywhere.
                return open(following: SyncLaunch.planAfterICloudStoreRefused)
            }

        case .local:
            if let local = try? HoursModelContainer.make(syncsWithICloud: false) {
                return (local, stopped, false)
            }
        }

        // Never refuse to start. A temporary store keeps the app usable and the
        // banner says so, which beats a blank screen over data nobody can reach.
        return (
            HoursModelContainer.ephemeral(),
            String(localized: "Your data could not be opened, so this session is temporary. Nothing you enter now will be saved."),
            false
        )
    }

    static var container: ModelContainer { opened.container }
    static var storeFailure: String? { opened.failure }

    /// Whether this session actually opened a syncing store — which is not the
    /// same as the preference being on, since the store may have refused.
    static var isSyncing: Bool { opened.isSyncing }

    /// Settings live in `UserDefaults`, not in the SwiftData store, so they
    /// need their own way across (`SettingsSync`). The key-value store is only
    /// reached once a syncing container has opened, which is the proof that
    /// this build actually carries the iCloud entitlement.
    static let settings: SettingsStore = {
        // Defaults, and a suite nothing else reads: a UI test asserting on
        // "8h 30m" must not fail because the person running it prefers 8.50.
        if isRunningUITests { return SettingsStore.ephemeral() }
        return SettingsStore(shared: isSyncing ? NSUbiquitousKeyValueStore.default : nil)
    }()

    /// What the syncing store has been doing. Started in the app's `init`.
    static let syncMonitor = SyncMonitor()

    static let clock: ActiveShiftStore = isRunningUITests
        ? ActiveShiftStore.ephemeral()
        : ActiveShiftStore()

    /// What has been paid for. Built once, because it holds a listener on the
    /// App Store for the life of the app — a second one would mean two answers
    /// to the same question.
    /// UI tests run as someone who has not paid unless they ask otherwise.
    /// That way the locks, the gates and the paywall are what gets exercised by
    /// default, and a test that wants the other side says so out loud.
    /// `-hours-as-shipped` is for the App Store screenshots: whatever the
    /// release offers for sale, so a free launch shows no purchase anywhere.
    static let subscriptions: SubscriptionStore = {
        guard isRunningUITests else { return SubscriptionStore(paymentsEnabled: FreeLaunch.paymentsEnabled) }
        let arguments = ProcessInfo.processInfo.arguments
        let paid = arguments.contains("-hours-pro")
        return SubscriptionStore.pinned(
            paid ? Entitlement(kind: .lifetime) : .free,
            paymentsEnabled: arguments.contains("-hours-as-shipped") ? FreeLaunch.paymentsEnabled : true
        )
    }()

    /// What a tapped notification asked to open (see `NotificationLinks`).
    static let notificationLinks = NotificationLinks()

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
        PeriodEngine(settings: settings.settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
    }
}
