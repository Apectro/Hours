import XCTest
@testable import Hours

/// TestFlight installs get Pro without paying; App Store installs never do.
final class TesterAccessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAppStoreInstallKeepsWhatTheStoreSaid() {
        let result = TesterAccess.entitlement(storeAnswer: .free, isTestFlight: false, testerLocksPro: false, at: now)

        XCTAssertEqual(result, .free, "a customer's free install must stay free")
    }

    func testAppStoreInstallWithALapsedPurchaseStaysLapsed() {
        let lapsed = Entitlement(kind: .subscription, expiresAt: now.addingTimeInterval(-60), checkedAt: now)

        let result = TesterAccess.entitlement(storeAnswer: lapsed, isTestFlight: false, testerLocksPro: false, at: now)

        XCTAssertEqual(result, lapsed)
        XCTAssertFalse(result.isActive(at: now))
    }

    func testTestFlightInstallUnlocksPro() {
        let result = TesterAccess.entitlement(storeAnswer: .free, isTestFlight: true, testerLocksPro: false, at: now)

        XCTAssertEqual(result.kind, .lifetime)
        XCTAssertTrue(result.isActive(at: now))
        XCTAssertTrue(result.allows(.multipleSites, at: now))
    }

    func testTesterCanSwitchTheUnlockOffToSeeThePaywall() {
        let result = TesterAccess.entitlement(storeAnswer: .free, isTestFlight: true, testerLocksPro: true, at: now)

        XCTAssertEqual(result, .free)
    }

    func testARealPurchaseIsNeverReplaced() {
        let bought = Entitlement(kind: .subscription, expiresAt: now.addingTimeInterval(3600), checkedAt: now)

        let unlocked = TesterAccess.entitlement(storeAnswer: bought, isTestFlight: true, testerLocksPro: false, at: now)
        let locked = TesterAccess.entitlement(storeAnswer: bought, isTestFlight: true, testerLocksPro: true, at: now)

        XCTAssertEqual(unlocked, bought, "what the tester actually bought is what they see")
        XCTAssertEqual(locked, bought, "switching the unlock off never hides a real purchase")
    }

    func testAnExpiredPurchaseOnTestFlightStillUnlocks() {
        let lapsed = Entitlement(kind: .subscription, expiresAt: now.addingTimeInterval(-60), checkedAt: now)

        let result = TesterAccess.entitlement(storeAnswer: lapsed, isTestFlight: true, testerLocksPro: false, at: now)

        XCTAssertTrue(result.isActive(at: now))
    }
}
