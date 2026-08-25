import Foundation
import Observation

/// Holds the running clock, if there is one.
///
/// Separate from `SettingsStore` because this is state, not preference: it
/// changes several times a day and means nothing once the shift is recorded.
/// Persisted so that quitting the app, or the phone restarting, does not lose
/// a shift that is still running.
@Observable
final class ActiveShiftStore {
    private(set) var running: RunningShift?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "hours.runningShift") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.running = ActiveShiftStore.load(from: defaults, key: storageKey)
    }

    var isRunning: Bool { running != nil }

    func start(_ shift: RunningShift) {
        running = shift
        persist()
    }

    /// Clears the clock and hands back what was running, so the caller can
    /// record it. Returns nil when nothing was running.
    @discardableResult
    func stop() -> RunningShift? {
        let finished = running
        running = nil
        persist()
        return finished
    }

    func updateJob(_ jobID: UUID?) {
        guard var shift = running else { return }
        shift.jobID = jobID
        running = shift
        persist()
    }

    private func persist() {
        guard let running else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(running) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> RunningShift? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RunningShift.self, from: data)
    }

    /// An isolated store for previews and tests.
    static func ephemeral() -> ActiveShiftStore {
        let suite = "hours.clock.preview.\(UUID().uuidString)"
        return ActiveShiftStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }
}
