import Foundation

/// Pro for people testing the app through TestFlight.
///
/// A TestFlight install is one the developer invited somebody to, so charging
/// them — even the sandbox's pretend charge — only gets in the way of testing.
/// The App Store build is untouched: the rule switches on solely for an install
/// that StoreKit itself reports as coming from TestFlight, so a customer can
/// never reach it.
///
/// The tester can switch it off, because the paywall and the purchase flow need
/// testing too. A real purchase always wins in both directions: the unlock never
/// replaces what somebody actually bought, and switching it off never hides it.
enum TesterAccess {
    static func entitlement(
        storeAnswer: Entitlement,
        isTestFlight: Bool,
        testerLocksPro: Bool,
        at instant: Date
    ) -> Entitlement {
        guard isTestFlight, !testerLocksPro, !storeAnswer.isActive(at: instant) else {
            return storeAnswer
        }
        return Entitlement(kind: .lifetime, checkedAt: instant)
    }
}
