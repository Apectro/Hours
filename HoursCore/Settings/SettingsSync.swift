import Foundation

/// Which copy of the settings a syncing device uses: its own, or the one in
/// the iCloud key-value store.
///
/// Settings live in `UserDefaults`, not in the SwiftData store, so they need
/// their own way across. The rule is iCloud's copy, last write wins — the
/// change a person just made on one of their own devices is the one they
/// meant — with two exceptions at the moment a device **joins**, the first
/// time it sees a copy in iCloud:
///
/// - **Its own custom day types are kept.** Days on this device carry their
///   ids; taking the other copy wholesale would turn them Unknown and change
///   what they count. iCloud's version wins where both have the same id.
/// - **Its own public-holiday rule ids are kept, for the same country's set.**
///   Both devices adding Austria makes two sets of rules; `HolidayDuplicates`
///   keeps one of each, and "Remove these holidays" must find whichever
///   survived.
///
/// Everything else — the week, pay, leave, the lock — is iCloud's, since one
/// person has one contract. Joining happens once per turning sync on, so a
/// type deleted on another device later stays deleted.
///
/// The first device to sync uploads what it has at launch. Before this it
/// waited for the next change, and a second device joining found nothing.
/// Writing before the key-value store's first download is safe: the system
/// discards the write and reports the download as a change, which is then
/// the moment of joining (`incoming`).
///
/// Not affected by any of this: the sync preference itself, which is the
/// installation's and never in settings (`SyncPreference`). A backup
/// restored on a syncing device replaces the settings on every device, as it
/// replaces the days on every device.
enum SettingsSync {
    struct Outcome: Equatable {
        var settings: AppSettings
        /// Write `settings` to this device's `UserDefaults`.
        var writesLocally: Bool
        /// Write `settings` to the key-value store.
        var pushes: Bool
        /// Whether this installation has joined iCloud's copy, to remember.
        var hasJoined: Bool
    }

    static func atLaunch(local: AppSettings?, remote: AppSettings?, hasJoined: Bool) -> Outcome {
        guard let remote else {
            return Outcome(settings: local ?? AppSettings(), writesLocally: false, pushes: local != nil, hasJoined: hasJoined)
        }
        let settings = hasJoined ? remote : joined(remote: remote, local: local)
        return Outcome(settings: settings, writesLocally: settings != local, pushes: settings != remote, hasJoined: true)
    }

    /// Another device's copy arrived while this one was running.
    static func incoming(_ remote: AppSettings, current: AppSettings, hasJoined: Bool) -> Outcome {
        let settings = hasJoined ? remote : joined(remote: remote, local: current)
        return Outcome(settings: settings, writesLocally: settings != current, pushes: settings != remote, hasJoined: true)
    }

    static func joined(remote: AppSettings, local: AppSettings?) -> AppSettings {
        guard let local else { return remote }
        var result = remote
        let known = Set(remote.customDayTypes.map(\.id))
        result.customDayTypes += local.customDayTypes.filter { !known.contains($0.id) }

        if let set = remote.publicHolidays.addedSetID, set == local.publicHolidays.addedSetID {
            let ids = remote.publicHolidays.addedRuleIDs
            result.publicHolidays.addedRuleIDs = ids + local.publicHolidays.addedRuleIDs.filter { !ids.contains($0) }
        }
        return result
    }
}
