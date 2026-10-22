import Foundation

/// Why sync is not running although it was asked for. Remembered (as its raw
/// value, in the installation's own `UserDefaults`) and shown in
/// Settings › iCloud as "Sync couldn't start: …" until sync is turned on again.
enum SyncProblem: String, Codable, CaseIterable, Equatable {
    /// This copy of the app is not signed to use iCloud — a build made without
    /// the capability, or without signing at all.
    case notSignedForICloud
    /// The app's own signature could not be read, so nobody can say whether it
    /// may use iCloud; treated as no.
    case signatureUnreadable
    /// The last launch began opening the syncing store and never finished:
    /// something killed it, and it would kill this one too.
    case stoppedDuringLaunch
    /// The syncing store threw instead of opening.
    case storeRefused
}

/// What one launch does about sync.
struct SyncLaunchPlan: Equatable {
    enum Store: Equatable {
        /// In memory and empty: UI tests.
        case temporary
        /// The store on this device, not mirrored.
        case local
        /// The same store file, mirrored to the user's private CloudKit database.
        case iCloud
    }

    let store: Store
    /// Turn the preference off, so the next launch does not try again.
    let switchesSyncOff: Bool
    /// Why sync was asked for and is not running; `nil` when nothing went wrong.
    let problem: SyncProblem?
    /// Leave a mark before opening the iCloud store, cleared once the store
    /// has proven itself. Any plan that does not set it clears a stale one.
    let marksOpening: Bool
}

/// The decision, kept apart from SwiftData and CloudKit so every path is
/// tested. Three defences, each enough on its own for the case it covers:
///
/// 1. **The signature.** A build is only allowed to open an iCloud store when
///    its own code signature says it may use the container
///    (`CodeSignatureEntitlements`). That is the exact cause of the 1.0 crash,
///    caught before anything is opened, so it costs not even one crash.
/// 2. **The mark.** Anything else that kills the process while the iCloud
///    store is being opened leaves the mark behind; the next launch sees it,
///    opens the local store and switches sync off. One crash, never a loop.
/// 3. **The fallback.** A store that throws instead is caught at once and the
///    local store opened (`planAfterICloudStoreRefused`).
///
/// Whichever stops sync, the hours are the same file either way, so nothing
/// recorded is out of reach — it is simply not being sent anywhere.
enum SyncLaunch {
    static func plan(
        isUITesting: Bool,
        wantsSync: Bool,
        isCompiledIn: Bool,
        entitlement: ICloudEntitlement,
        wasOpeningICloudStoreLastLaunch: Bool
    ) -> SyncLaunchPlan {
        // A test run starts from nothing and must not change the preference
        // of whoever runs it.
        if isUITesting {
            return SyncLaunchPlan(store: .temporary, switchesSyncOff: false, problem: nil, marksOpening: false)
        }
        // A build that cannot sync never offered the switch; a choice made in
        // one that could is kept for the next one that can.
        guard wantsSync, isCompiledIn else {
            return SyncLaunchPlan(store: .local, switchesSyncOff: false, problem: nil, marksOpening: false)
        }
        switch entitlement {
        case .missing:
            return local(because: .notSignedForICloud)
        case .unreadable:
            return local(because: .signatureUnreadable)
        case .present:
            break
        }
        if wasOpeningICloudStoreLastLaunch {
            return local(because: .stoppedDuringLaunch)
        }
        return SyncLaunchPlan(store: .iCloud, switchesSyncOff: false, problem: nil, marksOpening: true)
    }

    /// When the iCloud store threw rather than opened.
    static let planAfterICloudStoreRefused = local(because: .storeRefused)

    private static func local(because problem: SyncProblem) -> SyncLaunchPlan {
        SyncLaunchPlan(store: .local, switchesSyncOff: true, problem: problem, marksOpening: false)
    }

    /// Whether Settings shows the iCloud switch, and whether it can be used.
    enum Offer: Equatable {
        /// Not compiled in: no row at all, as in 1.0.
        case hidden
        case available
        /// Shown, switched off, with the reason.
        case unavailable(SyncProblem)
    }

    static func offer(isCompiledIn: Bool, entitlement: ICloudEntitlement) -> Offer {
        guard isCompiledIn else { return .hidden }
        switch entitlement {
        case .present: return .available
        case .missing: return .unavailable(.notSignedForICloud)
        case .unreadable: return .unavailable(.signatureUnreadable)
        }
    }

    /// How long a launch must survive with the iCloud store open before its
    /// mark is cleared, if CloudKit has not already reported its setup done.
    /// The exception that killed 1.0 is raised while the mirroring is being
    /// set up, within a second or two of the store opening.
    static let provingTime: TimeInterval = 20
}
