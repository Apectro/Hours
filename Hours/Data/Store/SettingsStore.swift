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

    init(defaults: UserDefaults = .standard, storageKey: String = "hours.settings") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.settings = SettingsStore.load(from: defaults, key: storageKey) ?? AppSettings()
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
    }

    private static func load(from defaults: UserDefaults, key: String) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    /// An isolated store for previews and tests.
    static func ephemeral(_ settings: AppSettings = AppSettings()) -> SettingsStore {
        let suiteName = "hours.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = SettingsStore(defaults: defaults, storageKey: "hours.settings")
        store.replace(with: settings)
        return store
    }
}
