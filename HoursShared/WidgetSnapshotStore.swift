import Foundation

// Code shared by the app and the widget extension that is not portable.
//
// `HoursCore` is the calculation engine and is built on Linux as well as iOS,
// which is what stops an Apple framework quietly getting into it. This file
// wants `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`,
// which exists on Apple platforms and nowhere else — so it lives beside the
// engine rather than inside it. The snapshot itself, being arithmetic and
// Codable, stays in the engine where the tests can reach it.

/// Where the snapshot lives, and how both sides find it.
///
/// The app group has to be configured in both targets' entitlements before the
/// widget can read anything. Until it is, `containerURL` is nil, writing is a
/// no-op and the widget shows its placeholder — which is the honest outcome,
/// rather than the app appearing to work while the widget silently shows
/// nothing.
enum WidgetSnapshotStore {
    /// Change this alongside the entitlements if the bundle identifier changes.
    /// Changing this orphans whatever the widget already wrote, so it was
    /// worth changing before anybody had a widget rather than after.
    static let appGroupIdentifier = "group.app.zeitkonto"

    static let fileName = "widget-snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    /// True when the app group is actually available to this process.
    static var isConfigured: Bool { containerURL != nil }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let fileURL else { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
