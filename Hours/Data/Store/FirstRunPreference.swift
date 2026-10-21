import Foundation

/// Whether this installation has been through the first-run setup.
///
/// Kept out of `AppSettings` for the reason `SyncPreference` is: settings
/// travel in backups and through iCloud, and having been asked is a property
/// of this installation, not of the data. A restored backup should not make a
/// new phone skip the questions, nor a second device ask them again — the
/// second is handled anyway, since a device that has received settings is
/// not a fresh install (see `FirstRunSetup`).
enum FirstRunPreference {
    private static let key = "hours.firstRunSetupDone"

    /// Passed by the one UI test that walks through the setup. The others
    /// start from an empty store and default settings, which is exactly what
    /// a fresh install looks like, so without this they are never shown it.
    static let launchArgument = "-hours-first-run"

    static var isForced: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
