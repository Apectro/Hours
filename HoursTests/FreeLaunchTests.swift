import XCTest
@testable import Hours

/// The first release is free with everything unlocked; payments switch on
/// later. These pin the rule the store applies either way.
final class FreeLaunchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_500_000)

    func testWithPaymentsOffEveryoneHasEverything() {
        let access = FreeLaunch.entitlement(storeAnswer: .free, paymentsEnabled: false, at: now)
        XCTAssertTrue(access.isActive(at: now))
        for feature in ProFeature.allCases {
            XCTAssertTrue(access.allows(feature, at: now), "\(feature) stayed locked with payments off")
        }
    }

    func testWithPaymentsOnTheStoreDecides() {
        XCTAssertEqual(FreeLaunch.entitlement(storeAnswer: .free, paymentsEnabled: true, at: now), .free)
    }

    func testSomethingBoughtIsKeptAsItIs() {
        let bought = Entitlement(kind: .lifetime, checkedAt: now)
        XCTAssertEqual(FreeLaunch.entitlement(storeAnswer: bought, paymentsEnabled: false, at: now), bought)
        XCTAssertEqual(FreeLaunch.entitlement(storeAnswer: bought, paymentsEnabled: true, at: now), bought)
    }
}
