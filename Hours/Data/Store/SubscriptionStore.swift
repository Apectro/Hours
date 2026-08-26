import Foundation
import Observation
import StoreKit

/// Everything to do with being paid for.
///
/// The App Store is the only source of truth. There is no account to sign into
/// and no server of ours: a purchase belongs to the buyer's Apple ID, which is
/// what makes it appear on their other devices without anyone logging in
/// anywhere. `Transaction.currentEntitlements` is asked afresh on every launch
/// and whenever the App Store says something changed.
///
/// The one thing written down is a cache of the last answer, and only so that a
/// paying customer with no signal is not told to buy the app again. It can
/// extend what was already paid for, never invent it — see
/// `Entitlement.isTrustworthyOffline`.
@Observable
@MainActor
final class SubscriptionStore {
    enum ProductID {
        static let monthly = "com.hours.app.pro.monthly"
        static let yearly = "com.hours.app.pro.yearly"
        static let lifetime = "com.hours.app.pro.lifetime"

        static let all = [monthly, yearly, lifetime]

        /// The subscription group the two renewing products share. Must match
        /// App Store Connect and `Hours.storekit`; a typo here does not fail
        /// anything loudly, it just silently stops billing retries being
        /// noticed, so it lives next to the ids rather than inline.
        static let subscriptionGroup = "hours.pro"
    }

    /// What a purchase attempt did, in the app's own words.
    enum PurchaseOutcome: Equatable {
        case bought
        case pending
        case cancelled
        case failed(String)
    }

    private(set) var entitlement: Entitlement
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    /// Set when the App Store could not be reached at all, so the paywall can
    /// say so instead of showing an empty list and looking broken.
    private(set) var loadFailure: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheKey: String
    @ObservationIgnored private var updates: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, cacheKey: String = "hours.entitlement") {
        self.defaults = defaults
        self.cacheKey = cacheKey
        self.entitlement = SubscriptionStore.cached(from: defaults, key: cacheKey) ?? .free

        // A transaction can arrive at any moment — a renewal, a refund, a
        // purchase made on another device, a family member sharing. Listening
        // for the life of the app is what Apple asks for, and it is why the
        // entitlement does not need polling.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = update {
                    await transaction.finish()
                }
                await self.refresh()
            }
        }
    }

    deinit { updates?.cancel() }

    var isPro: Bool { entitlement.isActive(at: Date()) }

    func allows(_ feature: ProFeature) -> Bool {
        entitlement.allows(feature, at: Date())
    }

    // MARK: - Reading the App Store

    /// Recomputes the entitlement from the transactions Apple currently
    /// recognises.
    func refresh(at instant: Date = Date()) async {
        var kind: Entitlement.Kind = .free
        var expiresAt: Date?
        var isRetrying = false

        for await result in Transaction.currentEntitlements {
            // An unverified transaction is one Apple will not vouch for. It is
            // ignored rather than trusted, which is the whole point of asking.
            guard case let .verified(transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }

            if transaction.productID == ProductID.lifetime {
                kind = .lifetime
                expiresAt = nil
                break
            }

            kind = .subscription
            // Several subscriptions can be present at once — an upgrade, or a
            // renewal overlapping. The furthest-out expiry is the one that
            // matters.
            if let date = transaction.expirationDate, date > (expiresAt ?? .distantPast) {
                expiresAt = date
            }
        }

        if kind == .subscription {
            isRetrying = await isInBillingRetry()
        }

        let fresh = Entitlement(
            kind: kind,
            expiresAt: expiresAt,
            isInBillingRetry: isRetrying,
            checkedAt: instant
        )

        // Nothing came back. That is either a genuine lapse or a device that
        // cannot reach the App Store, and the two look identical from here —
        // so a recent paid answer is kept rather than thrown away.
        if kind == .free, entitlement.isTrustworthyOffline(at: instant) {
            return
        }

        apply(fresh)
    }

    /// Whether the App Store is retrying a failed renewal, which is not a
    /// cancellation and usually not something the person knows about.
    private func isInBillingRetry() async -> Bool {
        guard let statuses = try? await Product.SubscriptionInfo.status(for: ProductID.subscriptionGroup) else {
            return false
        }
        return statuses.contains { $0.state == .inBillingRetryPeriod || $0.state == .inGracePeriod }
    }

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        loadFailure = nil
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: ProductID.all)
            // Cheapest first, with the outright purchase last: it is the
            // largest number and reads as the alternative it is.
            products = loaded.sorted { a, b in
                if a.id == ProductID.lifetime { return false }
                if b.id == ProductID.lifetime { return true }
                return a.price < b.price
            }
        } catch {
            loadFailure = "The App Store could not be reached. Your hours are unaffected — try again in a moment."
        }
    }

    // MARK: - Buying

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    return .failed("That purchase could not be verified with the App Store.")
                }
                await transaction.finish()
                await refresh()
                return .bought

            case .pending:
                // Ask to Buy, or a payment method needing action. It may be
                // approved later, and the updates listener will notice.
                return .pending

            case .userCancelled:
                return .cancelled

            @unknown default:
                return .failed("That purchase ended in a way this version does not recognise.")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Purchases follow the Apple ID, so this is rarely needed — but the App
    /// Store requires the button to exist, and it is the honest answer to
    /// "I already paid for this".
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return isPro
    }

    // MARK: - The cache

    private func apply(_ fresh: Entitlement) {
        entitlement = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private static func cached(from defaults: UserDefaults, key: String) -> Entitlement? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Entitlement.self, from: data)
    }

    /// An isolated store for previews and tests.
    static func ephemeral(_ entitlement: Entitlement = .free) -> SubscriptionStore {
        let defaults = UserDefaults(suiteName: "hours.preview.\(UUID().uuidString)") ?? .standard
        let store = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")
        store.entitlement = entitlement
        return store
    }
}
