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

    /// How long a cached answer may be trusted without hearing from the App
    /// Store again.
    ///
    /// The failure this exists for is a paying customer opening the app on a
    /// plane and being told to buy it again. Weighed against someone keeping
    /// the features for a fortnight after cancelling, which costs nothing and
    /// which they will not notice, the choice is not close.
    static let cacheGrace: TimeInterval = 14 * 24 * 60 * 60

    /// Whether a stored answer is still worth believing when the App Store
    /// cannot be reached. Only ever extends what was already paid for; it
    /// cannot turn a `.free` into anything.
    func isTrustworthyOffline(at instant: Date) -> Bool {
        guard kind != .free else { return false }
        guard instant >= checkedAt else { return true }
        return instant.timeIntervalSince(checkedAt) < Entitlement.cacheGrace
    }
}
