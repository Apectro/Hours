import XCTest
@testable import Hours

/// Which store a launch opens, and what it remembers about it.
///
/// The rule all of these serve: no build may crash at launch because of sync.
/// 1.0 in TestFlight did, at every launch, because it opened a syncing store
/// without being signed for iCloud and the choice to sync was remembered.
final class SyncLaunchTests: XCTestCase {
    private func plan(
        uiTesting: Bool = false,
        wantsSync: Bool = true,
        compiledIn: Bool = true,
        entitlement: ICloudEntitlement = .present,
        wasOpening: Bool = false
    ) -> SyncLaunchPlan {
        SyncLaunch.plan(
            isUITesting: uiTesting,
            wantsSync: wantsSync,
            isCompiledIn: compiledIn,
            entitlement: entitlement,
            wasOpeningICloudStoreLastLaunch: wasOpening
        )
    }

    // MARK: - The ordinary cases

    func testSyncOffOpensTheLocalStoreAndSaysNothing() {
        let plan = plan(wantsSync: false)
        XCTAssertEqual(plan.store, .local)
        XCTAssertNil(plan.problem)
        XCTAssertFalse(plan.switchesSyncOff)
        XCTAssertFalse(plan.marksOpening)
    }

    func testSyncOnInASignedBuildOpensTheICloudStoreAndMarksIt() {
        let plan = plan()
        XCTAssertEqual(plan.store, .iCloud)
        XCTAssertNil(plan.problem)
        XCTAssertFalse(plan.switchesSyncOff)
        XCTAssertTrue(plan.marksOpening, "an iCloud open that kills the process must leave a mark behind")
    }

    func testUITestsNeverOpenAnICloudStoreWhateverIsSaved() {
        // The CI simulator build is compiled with ICLOUD_SYNC but unsigned.
        for entitlement in [ICloudEntitlement.present, .missing, .unreadable] {
            let plan = plan(uiTesting: true, wantsSync: true, entitlement: entitlement, wasOpening: true)
            XCTAssertEqual(plan.store, .temporary)
            XCTAssertNil(plan.problem)
            XCTAssertFalse(plan.switchesSyncOff, "a test run must not change the machine's own preference")
            XCTAssertFalse(plan.marksOpening)
        }
    }

    // MARK: - The 1.0 crash, and its relatives

    func testABuildNotSignedForICloudOpensLocallyAndSwitchesSyncOff() {
        let plan = plan(entitlement: .missing)
        XCTAssertEqual(plan.store, .local)
        XCTAssertEqual(plan.problem, .notSignedForICloud)
        XCTAssertTrue(plan.switchesSyncOff)
        XCTAssertFalse(plan.marksOpening)
    }

    func testASignatureNobodyCanReadIsTreatedAsNoPermission() {
        let plan = plan(entitlement: .unreadable)
        XCTAssertEqual(plan.store, .local)
        XCTAssertEqual(plan.problem, .signatureUnreadable)
        XCTAssertTrue(plan.switchesSyncOff)
    }

    func testALaunchThatDiedOpeningTheICloudStoreIsNotRepeated() {
        // The mark is still there: the last launch began opening the iCloud
        // store and never got as far as clearing it. Whatever killed it would
        // kill this one too.
        let plan = plan(wasOpening: true)
        XCTAssertEqual(plan.store, .local)
        XCTAssertEqual(plan.problem, .stoppedDuringLaunch)
        XCTAssertTrue(plan.switchesSyncOff)
        XCTAssertFalse(plan.marksOpening, "the mark is cleared, so the launch after this one starts clean")
    }

    func testALeftOverMarkWithSyncOffIsJustCleared() {
        let plan = plan(wantsSync: false, wasOpening: true)
        XCTAssertEqual(plan.store, .local)
        XCTAssertNil(plan.problem)
        XCTAssertFalse(plan.marksOpening)
    }

    func testABuildCompiledWithoutSyncIgnoresTheSavedChoiceQuietly() {
        // A build without ICLOUD_SYNC never offers the switch, so there is
        // nothing to explain and the choice is kept for a build that has it.
        let plan = plan(compiledIn: false, entitlement: .missing)
        XCTAssertEqual(plan.store, .local)
        XCTAssertNil(plan.problem)
        XCTAssertFalse(plan.switchesSyncOff)
        XCTAssertFalse(plan.marksOpening)
    }

    func testAStoreThatRefusesToOpenFallsBackLocallyWithSyncOff() {
        let plan = SyncLaunch.planAfterICloudStoreRefused
        XCTAssertEqual(plan.store, .local)
        XCTAssertEqual(plan.problem, .storeRefused)
        XCTAssertTrue(plan.switchesSyncOff)
        XCTAssertFalse(plan.marksOpening)
    }

    /// Every input there is, against the one promise: an iCloud store is only
    /// ever opened by a launch that is signed for it, has no mark left by a
    /// launch that died, is not a test run, and was asked to.
    func testNoCombinationOpensICloudUnlessEverythingAllowsIt() {
        for uiTesting in [false, true] {
            for wantsSync in [false, true] {
                for compiledIn in [false, true] {
                    for entitlement in [ICloudEntitlement.present, .missing, .unreadable] {
                        for wasOpening in [false, true] {
                            let plan = plan(
                                uiTesting: uiTesting, wantsSync: wantsSync, compiledIn: compiledIn,
                                entitlement: entitlement, wasOpening: wasOpening
                            )
                            let allowed = !uiTesting && wantsSync && compiledIn && entitlement == .present && !wasOpening
                            XCTAssertEqual(plan.store == .iCloud, allowed, "\(uiTesting) \(wantsSync) \(compiledIn) \(entitlement) \(wasOpening)")
                            XCTAssertEqual(plan.marksOpening, plan.store == .iCloud)
                            if plan.problem != nil { XCTAssertTrue(plan.switchesSyncOff) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offering the switch

    func testTheSwitchIsOfferedOnlyInABuildSignedForICloud() {
        XCTAssertEqual(SyncLaunch.offer(isCompiledIn: false, entitlement: .present), .hidden)
        XCTAssertEqual(SyncLaunch.offer(isCompiledIn: true, entitlement: .present), .available)
        XCTAssertEqual(SyncLaunch.offer(isCompiledIn: true, entitlement: .missing), .unavailable(.notSignedForICloud))
        XCTAssertEqual(SyncLaunch.offer(isCompiledIn: true, entitlement: .unreadable), .unavailable(.signatureUnreadable))
    }

    // MARK: - Remembering a problem

    func testAProblemSurvivesTheTripThroughUserDefaults() {
        for problem in SyncProblem.allCases {
            XCTAssertEqual(SyncProblem(rawValue: problem.rawValue), problem)
        }
        XCTAssertNil(SyncProblem(rawValue: "something a later version wrote"))
    }
}
