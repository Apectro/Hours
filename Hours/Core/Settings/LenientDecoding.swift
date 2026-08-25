import Foundation

/// Settings are a long-lived, evolving blob. Decoding them strictly would mean
/// that adding one field in a future version invalidates every stored
/// preference, so every settings type decodes leniently: a missing or
/// unreadable key falls back to its default instead of failing the whole load.
///
/// This is the settings half of the migration strategy; see `SettingsStore`
/// for versioning.
extension KeyedDecodingContainer {
    /// `try?` flattens the nested optional, so a missing key and an unreadable
    /// value both arrive here as nil and both fall back.
    func lenient<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// Optional-valued properties, where "absent" and "explicitly null" mean
    /// the same thing.
    func lenientOptional<T: Decodable>(_ key: Key, _ type: T.Type = T.self) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
