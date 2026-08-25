import Foundation

/// Whether this device syncs through iCloud.
///
/// Kept out of `AppSettings` on purpose. Settings travel in a backup file, and
/// restoring a backup taken on a synced device onto one that is not — or onto
/// someone else's phone — must not quietly start uploading their hours. This is
/// a property of the installation, not of the data.
///
/// It is read once, before the store is opened, because a `ModelContainer`'s
/// CloudKit configuration is fixed at the moment it is created.
enum SyncPreference {
    private static let key = "hours.syncsWithICloud"

    /// The CloudKit container. Must match the iCloud capability in the app's
    /// entitlements, if one has been added.
    static let containerIdentifier = "iCloud.com.hours.app"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
