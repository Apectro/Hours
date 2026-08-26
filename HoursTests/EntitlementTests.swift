import XCTest
@testable import Hours

/// What the paid features are open for, and when.
final class EntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_140_800)

    private func subscription(expiringIn days: Double, retrying: Bool = false, checkedAt: Date? = nil) -> Entitlement {
        Entitlement(
            kind: .subscription,
            expiresAt: now.addingTimeInterval(days * 24 * 3600),
            isInBillingRetry: retrying,
            checkedAt: checkedAt ?? now
        )
    }

    // MARK: - The basic states

    func testNothingIsOpenWithoutAPurchase() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(Entitlement.free.allows(feature, at: now), "\(feature) should be paid for")
        }
    }

    func testALiveSubscriptionOpensEverything() {
        let entitlement = subscription(expiringIn: 20)

        for feature in ProFeature.allCases {
            XCTAssertTrue(entitlement.allows(feature, at: now))
        }
    }

    func testAnExpiredSubscriptionCloses() {
        XCTAssertFalse(subscription(expiringIn: -1).isActive(at: now))
    }

    /// Bought outright. There is no renewal to fail and no date to pass.
    func testLifetimeNeverExpires() {
        let entitlement = Entitlement(kind: .lifetime, checkedAt: now)
        let inTenYears = now.addingTimeInterval(10 * 365 * 24 * 3600)

        XCTAssertTrue(entitlement.isActive(at: now))
        XCTAssertTrue(entitlement.isActive(at: inTenYears))
    }

    /// A card that failed to charge is not a cancellation, and the person
    /// usually has no idea anything is wrong.
    func testABillingRetryKeepsEverythingOpen() {
        XCTAssertTrue(subscription(expiringIn: -2, retrying: true).isActive(at: now))
    }

    // MARK: - The provisional answer shown at launch

    /// Not about being offline — StoreKit's own entitlements are cached on the
    /// device and need no network. This is the second between launch and
    /// StoreKit replying, which a subscriber should not spend looking at a
    /// paywall.
    func testARecentAnswerIsWorthShowingWhileTheRealOneLoads() {
        let checkedThreeDaysAgo = subscription(expiringIn: 20, checkedAt: now.addingTimeInterval(-3 * 24 * 3600))

        XCTAssertTrue(checkedThreeDaysAgo.isTrustworthyOffline(at: now))
    }

    func testAVeryOldAnswerIsNotEvenWorthShowing() {
        let checkedLastMonth = subscription(expiringIn: 20, checkedAt: now.addingTimeInterval(-30 * 24 * 3600))

        XCTAssertFalse(checkedLastMonth.isTrustworthyOffline(at: now))
    }

    /// The cache may extend what was paid for. It may never invent it.
    func testACachedFreeAnswerCannotBecomeAnything() {
        let recentlyChecked = Entitlement(kind: .free, checkedAt: now)

        XCTAssertFalse(recentlyChecked.isTrustworthyOffline(at: now))
        XCTAssertFalse(recentlyChecked.isActive(at: now))
    }

    /// A device whose clock is behind the last check — a manual clock change,
    /// or a restore — must not fall through into an unbounded interval.
    func testAClockBehindTheLastCheckIsStillTrusted() {
        let checkedInTheFuture = subscription(expiringIn: 20, checkedAt: now.addingTimeInterval(3600))

        XCTAssertTrue(checkedInTheFuture.isTrustworthyOffline(at: now))
    }

    // MARK: - What may never be sold

    /// The rule the feature list is written under. If a future case makes
    /// recording, reading or exporting a backup conditional on paying, this is
    /// the test that should stop it.
    func testRecordingAndGettingYourDataOutAreNotForSale() {
        let sold = Set(ProFeature.allCases.map(\.rawValue))

        XCTAssertFalse(sold.contains("backup"))
        XCTAssertFalse(sold.contains("dayEditing"))
        XCTAssertFalse(sold.contains("calendar"))
        XCTAssertFalse(sold.contains("balance"))
        XCTAssertEqual(
            ProFeature.allCases.count, 5,
            "adding a paid feature is a product decision — update ProFeature.alwaysFree and this test deliberately"
        )
    }

    func testEveryPaidFeatureExplainsItself() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertFalse(feature.explanation.isEmpty, "\(feature) needs a reason someone would pay for it")
            XCTAssertFalse(feature.symbolName.isEmpty)
        }
    }

    func testAnEntitlementSurvivesBeingCached() throws {
        let original = subscription(expiringIn: 20, retrying: true)
        let data = try JSONEncoder().encode(original)

        XCTAssertEqual(try JSONDecoder().decode(Entitlement.self, from: data), original)
    }
}
