import Foundation

/// The first release is free, with every Pro feature unlocked for everyone.
///
/// Selling Pro needs Apple's paid-apps agreement, a bank account and tax forms,
/// which take time to set up from Croatia; the owner chose to launch without
/// payments rather than wait. The paywall, the products and the purchase code
/// all stay in place, switched off here, so turning payments on later is this
/// one constant and a new build.
///
/// When they are switched on, anyone who already used a Pro feature for free
/// is locked out of it until they buy — decide before flipping this whether
/// early users get a grace period or a lifetime unlock.
enum FreeLaunch {
    static let paymentsEnabled = false

    /// What the app treats as paid for. With payments off everyone gets the
    /// lifetime unlock; with them on, the App Store's answer stands. Something
    /// actually bought is passed through untouched either way, so a sandbox or
    /// later purchase never reads as less than it is.
    static func entitlement(storeAnswer: Entitlement, paymentsEnabled: Bool, at instant: Date) -> Entitlement {
        guard !paymentsEnabled, !storeAnswer.isActive(at: instant) else { return storeAnswer }
        return Entitlement(kind: .lifetime, checkedAt: instant)
    }
}
