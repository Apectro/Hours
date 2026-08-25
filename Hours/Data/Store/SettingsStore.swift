import Foundation
import Observation

/// Owns the user's settings and persists them.
///
/// Settings are stored as a single JSON blob in `UserDefaults`: they are read
/// on nearly every view update and passed by value into every calculation, so
/// a queryable store would buy nothing and cost a fetch each time.
@Observable
final class SettingsStore {
    private(set) var settings: AppSettings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    /// Present only when sync is on. Settings are not in the SwiftData store,
    /// so they would otherwise stay behind while the days went across — and a
    /// second device with a different contracted week does not merely look
    /// wrong, it computes the wrong expected hours for days it did not enter.
    @ObservationIgnored private let shared: NSUbiquitousKeyValueStore?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "hours.settings",
        // Passed in rather than decided here: touching the key-value store at
        // all is only safe once a syncing store has actually opened, which is
        // the proof the iCloud entitlement is present.
        shared: NSUbiquitousKeyValueStore? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.shared = shared

        let local = SettingsStore.load(from: defaults, key: storageKey)
        let remote = shared.flatMap { SettingsStore.decode($0.data(forKey: storageKey)) }
        // On a device joining an existing sync, the remote copy is the one the
        // other devices are already computing from; a device with settings of
        // its own has already written them up, so the two agree. Preferring
        // local here would mean a new phone's defaults overwriting a schedule
        // set up months ago.
        self.settings = remote ?? local ?? AppSettings()

        if let shared {
            shared.synchronize()
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: shared,
                queue: .main
            ) { [weak self] _ in
                self?.pullFromShared()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The only way to change settings, so persistence can never be forgotten.
    func update(_ transform: (inout AppSettings) -> Void) {
        var draft = settings
        transform(&draft)
        guard draft != settings else { return }
        settings = draft
        persist()
    }

    func replace(with newSettings: AppSettings) {
        settings = newSettings
        persist()
    }

    func resetToDefaults() {
        replace(with: AppSettings())
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
        shared?.set(data, forKey: storageKey)
    }

    /// Another device changed the settings. Last write wins, which is what the
    /// key-value store gives us anyway, and is the right rule for a single
    /// person's own devices: the change they just made is the one they meant.
    private func pullFromShared() {
        guard
            let shared,
            let incoming = SettingsStore.decode(shared.data(forKey: storageKey)),
            incoming != settings
        else { return }
        settings = incoming
        guard let data = try? JSONEncoder().encode(incoming) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func decode(_ data: Data?) -> AppSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private static func load(from defaults: UserDefaults, key: String) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// An isolated store for previews and tests.
    static func ephemeral(_ settings: AppSettings = AppSettings()) -> SettingsStore {
        let suiteName = "hours.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = SettingsStore(defaults: defaults, storageKey: "hours.settings", shared: nil)
        store.replace(with: settings)
        return store
    }
}
