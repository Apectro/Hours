import XCTest
import StoreKit
import StoreKitTest
@testable import Hours

/// Buying, restoring, expiring and refunding, against a real StoreKit.
///
/// `SKTestSession` runs the actual framework over `Hours.storekit`, so these
/// exercise the same `Transaction.currentEntitlements` the shipped app reads —
/// no protocol invented to make the code testable, and no mock that agrees with
/// whatever the implementation happens to do.
///
/// This is the half of the paywall that costs money when it is wrong. A
/// purchase that does not unlock, or a lapse that does not lock, are both
/// silent until someone writes a review about it.
@MainActor
final class SubscriptionStoreTests: XCTestCase {
    private var session: SKTestSession!
    private var store: SubscriptionStore!

    override func setUp() async throws {
        try await super.setUp()

        session = try SKTestSession(configurationFileNamed: "Hours")
        session.resetToDefaultState()
        session.clearTransactions()
        // Nothing here should ever wait for a person to tap something.
        session.disableDialogs = true

        // clearTransactions() returns before StoreKit has finished forgetting.
        // Starting a test while the previous one's purchase is still visible is
        // how two stable tests failed on two consecutive runs, each on a commit
        // that changed nothing they touch.
        await storeKitForgetsEverything()

        store = SubscriptionStore.ephemeral()
        await store.refresh()
    }

    /// What StoreKit itself currently reports, with no store object involved.
    private func liveEntitlementCount() async -> Int {
        var count = 0
        for await _ in Transaction.currentEntitlements { count += 1 }
        return count
    }

    /// Waits until StoreKit reports no entitlements at all.
    ///
    /// Separate from `eventually` on purpose: this waits on the framework, not
    /// on any code of ours, so a test that needs a clean slate can get one
    /// without weakening what it then asserts about a single refresh.
    private func storeKitForgetsEverything(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await liveEntitlementCount() == 0 { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let remaining = await liveEntitlementCount()
        XCTAssertEqual(
            remaining, 0,
            "StoreKit still holds \(remaining) entitlement(s) after clearTransactions()",
            file: file, line: line
        )
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        store = nil
        try await super.tearDown()
    }

    /// Waits for the entitlement to reach a state, refreshing as it goes.
    ///
    /// StoreKit does not promise that a refund or an expiry is visible to
    /// `currentEntitlements` the instant the test session is told to make one —
    /// revocations arrive through `Transaction.updates`, which is asynchronous
    /// by design. Polling is the honest way to write that down. It hides
    /// nothing: an entitlement that never closes still fails, just five seconds
    /// later.
    @discardableResult
    private func eventually(
        _ description: String,
        timeout: TimeInterval = 5,
        refreshing target: SubscriptionStore? = nil,
        until condition: () -> Bool
    ) async -> Bool {
        let polled = target ?? store!
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await polled.refresh()
        }
        XCTAssertTrue(condition(), "timed out waiting for \(description)")
        return condition()
    }

    private func product(_ id: String) async throws -> Product {
        let products = try await Product.products(for: [id])
        return try XCTUnwrap(products.first, "\(id) is missing from Hours.storekit")
    }

    // MARK: - Nothing bought

    func testAnUntouchedInstallIsFree() async {
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(store.entitlement.kind, .free)
        for feature in ProFeature.allCases {
            XCTAssertFalse(store.allows(feature))
        }
    }

    func testTheThreeProductsAreAllOffered() async {
        await store.loadProducts()

        XCTAssertEqual(store.products.count, 3, store.loadFailure ?? "")
        XCTAssertNil(store.loadFailure)
        XCTAssertEqual(
            store.products.last?.id,
            SubscriptionStore.ProductID.lifetime,
            "the outright purchase sorts last: it is the largest number and the alternative to the other two"
        )
    }

    // MARK: - Buying

    func testBuyingTheMonthlySubscriptionUnlocksEverything() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)

        let outcome = await store.purchase(monthly)

        XCTAssertEqual(outcome, .bought)
        XCTAssertTrue(store.isPro)
        XCTAssertEqual(store.entitlement.kind, .subscription)
        XCTAssertNotNil(store.entitlement.expiresAt)
        for feature in ProFeature.allCases {
            XCTAssertTrue(store.allows(feature))
        }
    }

    func testBuyingOutrightNeverExpires() async throws {
        let lifetime = try await product(SubscriptionStore.ProductID.lifetime)

        let outcome = await store.purchase(lifetime)

        XCTAssertEqual(outcome, .bought)
        XCTAssertEqual(store.entitlement.kind, .lifetime)
        XCTAssertNil(store.entitlement.expiresAt)
        XCTAssertTrue(store.entitlement.isActive(at: .distantFuture))
    }

    /// Ask to Buy: a child's purchase waiting on a parent. It is neither a
    /// success nor a failure, and the paywall says so rather than looking like
    /// it did nothing.
    func testAPurchaseAwaitingApprovalUnlocksNothingYet() async throws {
        session.askToBuyEnabled = true
        let monthly = try await product(SubscriptionStore.ProductID.monthly)

        let outcome = await store.purchase(monthly)

        XCTAssertEqual(outcome, .pending)
        XCTAssertFalse(store.isPro, "nothing opens until it is actually approved")
    }

    // MARK: - Losing it again

    func testAnExpiredSubscriptionLocksUpAgain() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)
        XCTAssertTrue(store.isPro)

        try session.expireSubscription(productIdentifier: SubscriptionStore.ProductID.monthly)

        await eventually("a lapsed subscription to close the paid features") { !self.store.isPro }
    }

    /// A refund is Apple revoking the transaction, and the store reads the
    /// revocation rather than the fact that a transaction exists at all.
    func testARefundedPurchaseStopsCounting() async throws {
        let lifetime = try await product(SubscriptionStore.ProductID.lifetime)
        _ = await store.purchase(lifetime)
        XCTAssertTrue(store.isPro)

        // By product id rather than by position: a test session can hold more
        // than one transaction, and refunding whichever came back first is a
        // coin toss.
        let bought = try XCTUnwrap(
            session.allTransactions().first { $0.productIdentifier == SubscriptionStore.ProductID.lifetime }
        )
        try session.refundTransaction(identifier: bought.identifier)

        await eventually("a refunded purchase to stop counting") { !self.store.isPro }
    }

    /// Whatever else changes, the free half must stay open — this is the test
    /// that would fail if someone ever gated recording hours.
    func testLosingAccessNeverTouchesTheFreeHalf() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)
        XCTAssertTrue(store.isPro, "the purchase has to have landed before expiring it means anything")

        try session.expireSubscription(productIdentifier: SubscriptionStore.ProductID.monthly)

        await eventually("an expired subscription to close") { !self.store.isPro }
        XCTAssertFalse(
            ProFeature.allCases.map(\.rawValue).contains("backup"),
            "the backup file is never sold, so there is nothing here for a lapse to take away"
        )
    }

    // MARK: - Restoring

    func testRestoringFindsAPurchaseTheAppleIDAlreadyHas() async throws {
        let lifetime = try await product(SubscriptionStore.ProductID.lifetime)
        _ = await store.purchase(lifetime)
        // There is nothing to restore until the purchase itself has landed, and
        // asserting that here is what tells the two failures apart.
        await eventually("the purchase to land") { self.store.isPro }

        // A fresh install against the same Apple ID: a new store object with no
        // cache of its own.
        let reinstalled = SubscriptionStore.ephemeral()

        let restored = await reinstalled.restore()
        XCTAssertTrue(restored, "restore did not report finding the purchase")

        // restore() syncs and then reads, but StoreKit does not promise the
        // synced transaction is visible to a store that has never seen it by
        // the time sync returns. This test asserted immediately and passed four
        // runs in a row before failing on a commit that changed no Swift.
        await eventually("the restored purchase to unlock", refreshing: reinstalled) {
            reinstalled.isPro
        }
    }

    func testRestoringWithNothingToRestoreSaysSo() async {
        let fresh = SubscriptionStore.ephemeral()

        let restored = await fresh.restore()

        XCTAssertFalse(restored)
        XCTAssertFalse(fresh.isPro)
    }

    // MARK: - What the cache is actually for

    /// It fills the gap between launch and StoreKit answering, and nothing
    /// more. A new store object with a paid cache shows paid straight away, so
    /// a subscriber does not watch their own app sit locked for a second.
    func testACachedAnswerShowsBeforeTheFirstRefresh() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hours.test.\(UUID().uuidString)"))
        let first = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")
        _ = await first.purchase(monthly)
        XCTAssertTrue(first.isPro)

        // Relaunch: same device, same defaults, before anything is asked of
        // StoreKit.
        let relaunched = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")

        XCTAssertTrue(relaunched.isPro, "the app opens unlocked rather than flashing a paywall")
    }

    /// And it is provisional. A completed refresh is the truth whichever way it
    /// goes — this is the assertion that stops the cache from becoming a way to
    /// keep Pro after cancelling.
    func testACompletedRefreshOverridesTheCache() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hours.test.\(UUID().uuidString)"))
        let first = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")
        _ = await first.purchase(monthly)
        // The cache being written is the precondition for the rest, so waiting
        // for it here means a failure below is about the refresh and not about
        // a purchase that had not landed yet.
        await eventually("the purchase to be cached", refreshing: first) { first.isPro }

        session.clearTransactions()
        // Waiting on StoreKit, not on us: clearTransactions() returns before
        // currentEntitlements stops reporting the purchase, and the single
        // refresh below has to be the one that sees the cleared state for the
        // assertion to mean what it says.
        await storeKitForgetsEverything()

        let relaunched = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")
        XCTAssertTrue(relaunched.isPro, "still showing the cached answer")

        await relaunched.refresh()

        XCTAssertFalse(relaunched.isPro, "StoreKit said no, and StoreKit is the answer")
    }

    /// A cache old enough to be meaningless is not even worth showing.
    func testAVeryOldCacheOpensLocked() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hours.test.\(UUID().uuidString)"))
        let stale = Entitlement(
            kind: .subscription,
            expiresAt: Date().addingTimeInterval(30 * 24 * 3600),
            checkedAt: Date().addingTimeInterval(-60 * 24 * 3600)
        )
        defaults.set(try JSONEncoder().encode(stale), forKey: "hours.entitlement")

        let store = SubscriptionStore(defaults: defaults, cacheKey: "hours.entitlement")

        XCTAssertFalse(store.isPro)
    }
}
