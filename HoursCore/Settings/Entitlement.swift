import Foundation

/// What this installation is entitled to, and until when.
///
/// A value type with no StoreKit in it, so the rules can be tested exhaustively
/// and off-platform. `SubscriptionStore` builds one of these from the App
/// Store; nothing else is allowed to invent one.
///
/// Notably there is no `isPro: Bool` stored anywhere the user could reach. The
/// answer is derived from a transaction every time, and the only thing written
/// to disk is a cache that can expire — see `SubscriptionStore`.
struct Entitlement: Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case free
        case subscription
        /// Bought outright. Never expires, and no renewal to fail.
        case lifetime
    }

    var kind: Kind

    /// When the current period runs out. Always nil for `.free` and
    /// `.lifetime`.
    var expiresAt: Date?

    /// The App Store is retrying a failed renewal. The person has not
    /// cancelled and may well not know anything is wrong, so they keep
    /// everything until it resolves.
    var isInBillingRetry: Bool

    /// The last moment this was known to be true. A device that has been in a
    /// tunnel for a week has an old answer rather than no answer, and the two
    /// are treated differently.
    var checkedAt: Date

    static let free = Entitlement(kind: .free, expiresAt: nil, isInBillingRetry: false, checkedAt: .distantPast)

    init(kind: Kind, expiresAt: Date? = nil, isInBillingRetry: Bool = false, checkedAt: Date = Date()) {
        self.kind = kind
        self.expiresAt = expiresAt
        self.isInBillingRetry = isInBillingRetry
        self.checkedAt = checkedAt
    }

    /// Whether the paid features are open at a given moment.
    func isActive(at instant: Date) -> Bool {
        switch kind {
        case .free:
            return false
        case .lifetime:
            return true
        case .subscription:
            if isInBillingRetry { return true }
            guard let expiresAt else { return false }
            return instant < expiresAt
        }
    }

    func allows(_ feature: ProFeature, at instant: Date) -> Bool {
        isActive(at: instant)
    }

    /// How old a stored answer may be and still be worth showing while the
    /// real one is fetched.
    ///
    /// This is not about being offline — `Transaction.currentEntitlements`
    /// reads signed transactions held on the device and needs no network, so
    /// StoreKit has that covered. It is about the second between launch and
    /// StoreKit replying, which a subscriber should not spend looking at a
    /// paywall. A fortnight is generous for that purpose and harmless, because
    /// the first completed refresh overwrites it either way.
    static let cacheGrace: TimeInterval = 14 * 24 * 60 * 60

    /// Whether a stored answer is recent enough to show provisionally. Only
    /// ever about something already paid for; it cannot turn a `.free` into
    /// anything.
    func isTrustworthyOffline(at instant: Date) -> Bool {
        guard kind != .free else { return false }
        guard instant >= checkedAt else { return true }
        return instant.timeIntervalSince(checkedAt) < Entitlement.cacheGrace
    }
}
