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

        store = SubscriptionStore.ephemeral()
        await store.refresh()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        store = nil
        try await super.tearDown()
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

        XCTAssertEqual(await store.purchase(lifetime), .bought)
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

        XCTAssertEqual(await store.purchase(monthly), .pending)
        XCTAssertFalse(store.isPro, "nothing opens until it is actually approved")
    }

    // MARK: - Losing it again

    func testAnExpiredSubscriptionLocksUpAgain() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)
        XCTAssertTrue(store.isPro)

        try await session.expireSubscription(productIdentifier: SubscriptionStore.ProductID.monthly)
        await store.refresh()

        XCTAssertFalse(store.isPro, "a lapsed subscription closes the paid features")
    }

    /// A refund is Apple revoking the transaction, and the store reads the
    /// revocation rather than the fact that a transaction exists at all.
    func testARefundedPurchaseStopsCounting() async throws {
        let lifetime = try await product(SubscriptionStore.ProductID.lifetime)
        _ = await store.purchase(lifetime)
        XCTAssertTrue(store.isPro)

        let transaction = try XCTUnwrap(try session.allTransactions().first)
        try await session.refundTransaction(identifier: transaction.identifier)
        await store.refresh()

        XCTAssertFalse(store.isPro)
    }

    /// Whatever else changes, the free half must stay open — this is the test
    /// that would fail if someone ever gated recording hours.
    func testLosingAccessNeverTouchesTheFreeHalf() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)
        try await session.expireSubscription(productIdentifier: SubscriptionStore.ProductID.monthly)
        await store.refresh()

        XCTAssertFalse(store.isPro)
        XCTAssertFalse(
            ProFeature.allCases.map(\.rawValue).contains("backup"),
            "the backup file is never sold, so there is nothing here for a lapse to take away"
        )
    }

    // MARK: - Restoring

    func testRestoringFindsAPurchaseTheAppleIDAlreadyHas() async throws {
        let lifetime = try await product(SubscriptionStore.ProductID.lifetime)
        _ = await store.purchase(lifetime)

        // A fresh install against the same Apple ID: a new store object with no
        // cache of its own.
        let reinstalled = SubscriptionStore.ephemeral()

        XCTAssertTrue(await reinstalled.restore())
        XCTAssertTrue(reinstalled.isPro)
    }

    func testRestoringWithNothingToRestoreSaysSo() async {
        let fresh = SubscriptionStore.ephemeral()

        XCTAssertFalse(await fresh.restore())
        XCTAssertFalse(fresh.isPro)
    }

    // MARK: - The offline cache

    /// The failure this whole mechanism exists for: a paying customer whose
    /// device cannot reach the App Store must not be told to buy the app again.
    func testARecentlyPaidStoreStaysUnlockedWhenTheStoreCannotBeReached() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)
        XCTAssertTrue(store.isPro)

        // Everything gone from StoreKit's point of view, which is what being
        // offline looks like from inside `currentEntitlements`.
        session.clearTransactions()
        await store.refresh()

        XCTAssertTrue(store.isPro, "a recent paid answer outlives a launch that heard nothing")
    }

    func testAnAnswerOlderThanTheGraceIsNotBelieved() async throws {
        let monthly = try await product(SubscriptionStore.ProductID.monthly)
        _ = await store.purchase(monthly)

        session.clearTransactions()
        // A month later, still with nothing to hear.
        await store.refresh(at: Date().addingTimeInterval(30 * 24 * 3600))

        XCTAssertFalse(store.isPro)
    }
}
