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
/// The one thing written down is a cache of the last answer, and its only job is
/// to fill the moment between launch and StoreKit replying, so that a paying
/// customer does not watch their app sit locked for a second. It is provisional:
/// the first completed `refresh()` overwrites it either way. Being genuinely
/// offline needs no help from us — `currentEntitlements` reads signed
/// transactions held on the device.
@Observable
@MainActor
final class SubscriptionStore {
    enum ProductID {
        static let monthly = "app.zeitkonto.pro.monthly"
        static let yearly = "app.zeitkonto.pro.yearly"
        static let lifetime = "app.zeitkonto.pro.lifetime"

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
    /// This copy was installed from TestFlight, as StoreKit itself reports it.
    /// Only then does `TesterAccess` unlock Pro, and only then does Settings
    /// offer the switch that turns the unlock off.
    private(set) var isTestFlightInstall = false
    /// The tester turned the free unlock off, to see the app as a customer
    /// does. A property of this installation, never of the data.
    private(set) var testerLocksPro: Bool
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    /// Set when the App Store could not be reached at all, so the paywall can
    /// say so instead of showing an empty list and looking broken.
    private(set) var loadFailure: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cacheKey: String
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// A pinned store answers from what it was handed and never asks the App
    /// Store. Only the UI-test seam sets it, and it has to exist because
    /// `refresh()` is now unconditional: the app under test has no
    /// transactions, so the first refresh would overwrite the entitlement the
    /// test asked for with StoreKit's perfectly correct "nothing".
    @ObservationIgnored private let isPinned: Bool
    /// What the App Store itself said, before any TestFlight unlock. This is
    /// the only answer that is cached, so an install that moves from
    /// TestFlight to the App Store never starts out with an unlock it no
    /// longer has.
    @ObservationIgnored private var storeAnswer: Entitlement

    private static let testerLocksProKey = "hours.tester.locksPro"

    /// Whether this store sells anything. Only the app's own store is built
    /// with `FreeLaunch.paymentsEnabled`; every other store — the StoreKit
    /// tests, previews, the UI tests' pinned one — keeps purchases working,
    /// so the paywall and the purchase code stay tested while the first
    /// release is free.
    @ObservationIgnored let paymentsEnabled: Bool

    init(
        defaults: UserDefaults = .standard,
        cacheKey: String = "hours.entitlement",
        pinned: Bool = false,
        paymentsEnabled: Bool = true
    ) {
        self.isPinned = pinned
        self.paymentsEnabled = paymentsEnabled
        self.defaults = defaults
        self.cacheKey = cacheKey
        // Provisional, and only until the first `refresh()` returns: without it
        // a paying customer sees a locked app for the moment it takes StoreKit
        // to answer on launch. A stale one is not even worth that much.
        let cached = SubscriptionStore.cached(from: defaults, key: cacheKey)
        let provisional = cached?.isTrustworthyOffline(at: Date()) == true ? cached! : .free
        self.storeAnswer = provisional
        self.entitlement = FreeLaunch.entitlement(storeAnswer: provisional, paymentsEnabled: paymentsEnabled, at: Date())
        self.testerLocksPro = defaults.bool(forKey: SubscriptionStore.testerLocksProKey)

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

        // Asked here rather than only when the main screen appears: an App
        // Intent can wake the app in the background and write the widget,
        // and a TestFlight install must not be written as locked then.
        Task { [weak self] in await self?.detectInstallSource() }
    }

    deinit { updates?.cancel() }

    // MARK: - TestFlight

    /// Asks StoreKit where this copy came from. A sandbox app transaction is a
    /// TestFlight install (or a developer's own build); the App Store's is
    /// production, and an Xcode StoreKit session is neither.
    ///
    /// Compiled in only when the build asks for it (`TESTER_UNLOCK`, set by
    /// the TestFlight workflow's "Unlock Pro for testers" switch). App Review
    /// also runs in the sandbox, so the build submitted for review is made
    /// with the switch off and has no unlock in it at all.
    func detectInstallSource() async {
        #if TESTER_UNLOCK
        guard !isPinned else { return }
        guard case let .verified(transaction)? = try? await AppTransaction.shared else { return }
        isTestFlightInstall = transaction.environment == .sandbox
        applyTesterAccess()
        #endif
    }

    func setTesterLocksPro(_ locks: Bool) {
        guard !isPinned else { return }
        testerLocksPro = locks
        defaults.set(locks, forKey: SubscriptionStore.testerLocksProKey)
        applyTesterAccess()
    }

    private func applyTesterAccess() {
        let now = Date()
        let tested = TesterAccess.entitlement(
            storeAnswer: storeAnswer,
            isTestFlight: isTestFlightInstall,
            testerLocksPro: testerLocksPro,
            at: now
        )
        entitlement = FreeLaunch.entitlement(storeAnswer: tested, paymentsEnabled: paymentsEnabled, at: now)
    }

    /// Whether this copy of the app sells anything: the Pro row, the tester
    /// switch and "Buying Zeitkonto Pro" only appear when it does.
    var offersPurchases: Bool { paymentsEnabled }

    var isPro: Bool { entitlement.isActive(at: Date()) }

    func allows(_ feature: ProFeature) -> Bool {
        entitlement.allows(feature, at: Date())
    }

    // MARK: - Reading the App Store

    /// Recomputes the entitlement from the transactions Apple currently
    /// recognises.
    func refresh(at instant: Date = Date()) async {
        guard !isPinned else { return }

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

        // Whatever came back is the answer, including nothing.
        //
        // An earlier version kept a recent paid answer here, on the theory that
        // an empty result might mean a device that could not reach the App
        // Store. That was wrong, and the tests caught it: `currentEntitlements`
        // reads Apple-signed transactions cached on the device and does not
        // need the network, so empty means genuinely nothing — StoreKit has
        // already solved the offline problem, and second-guessing it only made
        // expiries and refunds take a fortnight to bite.
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
    ///
    /// Not covered end to end by a test, and deliberately so. `AppStore.sync()`
    /// empties an `SKTestSession` rather than re-delivering what it holds —
    /// measured, not assumed: an entitlement count of 1 before the call and 0
    /// after it, printed by the test that used to drive this path. So a test
    /// through here exercises the simulator's fidelity rather than this app,
    /// and fails at random depending on timing; it did, three times, and was
    /// twice misdiagnosed as a race.
    ///
    /// `testAFreshStoreFindsAPurchaseTheAppleIDAlreadyHas` covers the half that
    /// is ours: a store with no cache reading an entitlement StoreKit holds.
    /// The sync stays, because a Restore button that does not ask Apple to
    /// re-deliver is not a Restore button.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return isPro
    }

    // MARK: - The cache

    private func apply(_ fresh: Entitlement) {
        storeAnswer = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: cacheKey)
        }
        applyTesterAccess()
    }

    private static func cached(from defaults: UserDefaults, key: String) -> Entitlement? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Entitlement.self, from: data)
    }

    /// An isolated store for previews and for the StoreKit tests, which need
    /// `refresh()` to do its real work.
    static func ephemeral(_ entitlement: Entitlement = .free) -> SubscriptionStore {
        let defaults = UserDefaults(suiteName: "hours.preview.\(UUID().uuidString)") ?? .standard
        let store = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")
        store.storeAnswer = entitlement
        store.entitlement = entitlement
        return store
    }

    /// A store that will keep saying what it was told, whatever StoreKit
    /// thinks. For UI tests, which drive an app with no transactions in it.
    static func pinned(_ entitlement: Entitlement, paymentsEnabled: Bool = true) -> SubscriptionStore {
        let defaults = UserDefaults(suiteName: "hours.uitest.\(UUID().uuidString)") ?? .standard
        let store = SubscriptionStore(
            defaults: defaults, cacheKey: "hours.entitlement", pinned: true, paymentsEnabled: paymentsEnabled
        )
        store.storeAnswer = entitlement
        store.entitlement = entitlement
        return store
    }
}
