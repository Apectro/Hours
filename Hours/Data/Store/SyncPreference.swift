import Foundation

/// Whether this device syncs through iCloud, and whether it can.
///
/// Kept out of `AppSettings` on purpose. Settings travel in a backup file, and
/// restoring a backup taken on a synced device onto one that is not — or onto
/// someone else's phone — must not quietly start uploading their hours. This is
/// a property of the installation, not of the data.
///
/// It is read once, before the store is opened, because a `ModelContainer`'s
/// CloudKit configuration is fixed at the moment it is created. What a launch
/// does with it is `SyncLaunch.plan`, in the engine, where every path is
/// tested; `HoursStack` carries the plan out.
enum SyncPreference {
    /// `.v2` since 1.1. The choice saved by the 1.0 TestFlight builds that
    /// offered the switch was made in a build that could not keep it (it
    /// crashed); sync starts only on a choice made where it can.
    private static let key = "hours.syncsWithICloud.v2"
    private static let problemKey = "hours.syncProblem"

    /// The CloudKit container. Must match `Hours.entitlements` and the
    /// container ticked on the App ID (see the Fastfile's ICLOUD_FIX).
    static let containerIdentifier = "iCloud.app.zeitkonto"

    /// Whether this build was compiled to offer sync at all (`ICLOUD_SYNC`,
    /// set for the app target in Debug and Release).
    #if ICLOUD_SYNC
    static let isCompiledIn = true
    #else
    static let isCompiledIn = false
    #endif

    /// Whether this copy of the app is signed to use the container, read once
    /// from its own executable's code signature. Opening a syncing store
    /// without it does not throw: CloudKit raises an exception Swift cannot
    /// catch and the process dies, which is how 1.0 crashed at every launch.
    /// See `CodeSignatureEntitlements`.
    static let entitlement: ICloudEntitlement = {
        guard isCompiledIn else { return .missing }
        guard let url = Bundle.main.executableURL,
              // Mapped, so only the pages the header and signature are on are read.
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return .unreadable }
        return ICloudEntitlement.status(of: CodeSignatureEntitlements.read(data), container: containerIdentifier)
    }()

    /// Whether Settings shows the switch, and whether it can be used.
    static var offer: SyncLaunch.Offer {
        SyncLaunch.offer(isCompiledIn: isCompiledIn, entitlement: entitlement)
    }

    /// Whether sync can be turned on in this build.
    static var isAvailable: Bool { offer == .available }

    /// The choice as made. Whether this launch actually syncs is
    /// `HoursStack.isSyncing`, since the store may have refused.
    static var isEnabled: Bool {
        get { isCompiledIn && UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if newValue {
                // Trying again: the old reason no longer applies.
                problem = nil
            } else {
                // Turning sync on again later joins the settings in iCloud
                // afresh (see `SettingsSync`).
                UserDefaults.standard.removeObject(forKey: SettingsStore.joinedKey)
            }
        }
    }

    /// Why sync stopped, shown in Settings › iCloud until it is turned on
    /// again. A reason a later version wrote and this one does not know reads
    /// as none.
    static var problem: SyncProblem? {
        get { UserDefaults.standard.string(forKey: problemKey).flatMap(SyncProblem.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: problemKey) }
    }
}

/// The mark a launch leaves while it opens the iCloud store (see `SyncLaunch`).
///
/// A file rather than a `UserDefaults` key: defaults reach the disk a moment
/// after they are set, and the moment this has to survive is the process
/// being killed right after. Writing a file is done when it returns.
enum SyncLaunchMark {
    private static var url: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("opening-icloud-store.mark")
    }

    static var isSet: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func set() {
        guard let url else { return }
        try? Data("opening the iCloud store".utf8).write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
