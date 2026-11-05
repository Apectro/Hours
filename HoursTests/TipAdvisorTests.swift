import XCTest
@testable import Hours

/// Tips at the top of a screen (2026-11-05): which one a screen shows, if
/// any, and the switch and the dismissed set that live in the settings.
final class TipAdvisorTests: XCTestCase {
    // MARK: - Each condition

    /// The owner's case: a site with days or a crew and no work days set.
    func testASiteWithoutWorkDaysAsksForThem() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: true)
        XCTAssertEqual(TipAdvisor.tip(for: .site, facts: facts), .siteWorkDays)
    }

    /// A site nothing was done on yet has nothing to go wrong.
    func testAnEmptySiteHasNoWorkDaysTip() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: false)
        XCTAssertNil(TipAdvisor.tip(for: .site, facts: facts))
    }

    func testDaysNotWrittenPointAtTheRedCount() {
        let facts = TipFacts(siteHasWorkDays: true, siteHasDaysOrCrew: true, siteDaysNotWritten: 3)
        XCTAssertEqual(TipAdvisor.tip(for: .site, facts: facts), .siteDaysNotWritten)
    }

    func testASiteWithWorkDaysAndEverythingWrittenHasNoTip() {
        let facts = TipFacts(siteHasWorkDays: true, siteHasDaysOrCrew: true, siteDaysNotWritten: 0)
        XCTAssertNil(TipAdvisor.tip(for: .site, facts: facts))
    }

    /// A read-only site (the Pro rule) cannot be changed, so it is not
    /// told to.
    func testAReadOnlySiteHasNoTip() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: true, siteDaysNotWritten: 2, siteIsReadOnly: true)
        XCTAssertNil(TipAdvisor.tip(for: .site, facts: facts))
    }

    func testNoNameOnTheSheetsOnceThereIsSomethingToSend() {
        XCTAssertEqual(
            TipAdvisor.tip(for: .export, facts: TipFacts(ownerNameIsEmpty: true, hasSitesOrDays: true)),
            .ownerName
        )
        XCTAssertNil(TipAdvisor.tip(for: .export, facts: TipFacts(ownerNameIsEmpty: true, hasSitesOrDays: false)))
        XCTAssertNil(TipAdvisor.tip(for: .export, facts: TipFacts(ownerNameIsEmpty: false, hasSitesOrDays: true)))
    }

    func testScanTheBoxOnlyUntilMaterialWasAddedOnce() {
        let fresh = TipFacts(materialIsEmpty: true, scannerIsAvailable: true, materialUsedBefore: false)
        XCTAssertEqual(TipAdvisor.tip(for: .extraWorkEditor, facts: fresh), .scanMaterial)

        var withItem = fresh
        withItem.materialIsEmpty = false
        XCTAssertNil(TipAdvisor.tip(for: .extraWorkEditor, facts: withItem))

        var usedBefore = fresh
        usedBefore.materialUsedBefore = true
        XCTAssertNil(TipAdvisor.tip(for: .extraWorkEditor, facts: usedBefore))

        var noScanner = fresh
        noScanner.scannerIsAvailable = false
        XCTAssertNil(TipAdvisor.tip(for: .extraWorkEditor, facts: noScanner))
    }

    func testSwipeADayOnTheWeekList() {
        XCTAssertEqual(TipAdvisor.tip(for: .calendarWeek, facts: TipFacts(weekListIsShown: true)), .swipeDays)
        XCTAssertNil(TipAdvisor.tip(for: .calendarWeek, facts: TipFacts(weekListIsShown: false)))
    }

    func testPhotoFirstOnAnEmptyDefectsList() {
        XCTAssertEqual(TipAdvisor.tip(for: .defects, facts: TipFacts(defectsAreEmpty: true)), .defectPhotos)
        XCTAssertNil(TipAdvisor.tip(for: .defects, facts: TipFacts(defectsAreEmpty: false)))
    }

    /// Every tip belongs to exactly one screen, and a screen only ever
    /// offers its own.
    func testEachTipIsOnOneScreen() {
        for tip in TipID.allCases {
            XCTAssertEqual(TipScreen.allCases.filter { $0.tips.contains(tip) }, [tip.screen], "\(tip)")
        }
        let everything = TipFacts(
            siteHasWorkDays: false, siteHasDaysOrCrew: true, siteDaysNotWritten: 4,
            ownerNameIsEmpty: true, hasSitesOrDays: true,
            materialIsEmpty: true, scannerIsAvailable: true,
            weekListIsShown: true, defectsAreEmpty: true
        )
        for screen in TipScreen.allCases {
            let tip = TipAdvisor.tip(for: screen, facts: everything)
            XCTAssertEqual(tip?.screen, screen)
        }
    }

    /// The defaults show nothing anywhere: a screen that fills in only its
    /// own facts cannot pick up another screen's tip.
    func testTheDefaultFactsShowNothing() {
        for screen in TipScreen.allCases {
            XCTAssertNil(TipAdvisor.tip(for: screen, facts: TipFacts()), "\(screen)")
        }
    }

    // MARK: - Dismissed and disabled

    func testADismissedTipIsNotShown() {
        let facts = TipFacts(ownerNameIsEmpty: true, hasSitesOrDays: true)
        XCTAssertNil(TipAdvisor.tip(for: .export, facts: facts, dismissed: [.ownerName]))
        XCTAssertEqual(TipAdvisor.tip(for: .export, facts: facts, dismissed: [.swipeDays]), .ownerName)
    }

    func testTipsSwitchedOffShowNothing() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: true, siteDaysNotWritten: 2)
        XCTAssertNil(TipAdvisor.tip(for: .site, facts: facts, enabled: false))
    }

    // MARK: - Priority

    /// Both apply on the owner's site: the work days come first, since the
    /// red count goes by them.
    func testWorkDaysWinOverDaysNotWritten() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: true, siteDaysNotWritten: 5)
        XCTAssertEqual(TipAdvisor.tip(for: .site, facts: facts), .siteWorkDays)
    }

    /// The more relevant one dismissed, the next one shows.
    func testTheNextTipShowsWhenTheFirstIsDismissed() {
        let facts = TipFacts(siteHasWorkDays: false, siteHasDaysOrCrew: true, siteDaysNotWritten: 5)
        XCTAssertEqual(TipAdvisor.tip(for: .site, facts: facts, dismissed: [.siteWorkDays]), .siteDaysNotWritten)
    }

    // MARK: - The facts change

    /// Setting the work days takes the tip away by itself.
    func testSettingTheWorkDaysTakesTheTipAway() {
        let site = UUID()
        var settings = AppSettings()
        let before = TipFacts.site(setup: settings.siteSetup(for: site), siteDays: 1, crew: 2, daysNotWritten: 0, isReadOnly: false)
        XCTAssertEqual(settings.tip(for: .site, facts: before), .siteWorkDays)

        var setup = settings.siteSetup(for: site)
        setup.workDays = [2, 3, 4, 5, 6]
        settings.setSiteSetup(setup, for: site)
        let after = TipFacts.site(setup: settings.siteSetup(for: site), siteDays: 1, crew: 2, daysNotWritten: 0, isReadOnly: false)
        XCTAssertNil(settings.tip(for: .site, facts: after))
    }

    func testANameTypedTakesTheTipAway() {
        var settings = AppSettings()
        XCTAssertEqual(settings.tip(for: .export, facts: .export(ownerName: settings.export.ownerName, hasSitesOrDays: true)), .ownerName)
        settings.export.ownerName = "   "
        XCTAssertEqual(settings.tip(for: .export, facts: .export(ownerName: settings.export.ownerName, hasSitesOrDays: true)), .ownerName)
        settings.export.ownerName = "Ana Horvat"
        XCTAssertNil(settings.tip(for: .export, facts: .export(ownerName: settings.export.ownerName, hasSitesOrDays: true)))
    }

    func testTheSiteFactsCountACrewOrADay() {
        let none = SiteSetup()
        XCTAssertFalse(TipFacts.site(setup: none, siteDays: 0, crew: 0, daysNotWritten: 0, isReadOnly: false).siteHasDaysOrCrew)
        XCTAssertTrue(TipFacts.site(setup: none, siteDays: 1, crew: 0, daysNotWritten: 0, isReadOnly: false).siteHasDaysOrCrew)
        XCTAssertTrue(TipFacts.site(setup: none, siteDays: 0, crew: 1, daysNotWritten: 0, isReadOnly: false).siteHasDaysOrCrew)
    }

    // MARK: - The settings

    func testTipsAreOnWithNothingDismissedByDefault() {
        let tips = AppSettings().tips
        XCTAssertTrue(tips.isEnabled)
        XCTAssertTrue(tips.dismissed.isEmpty)
    }

    func testDismissingAndShowingAllAgain() {
        var settings = AppSettings()
        settings.tips.dismiss(.defectPhotos)
        settings.tips.dismiss(.swipeDays)
        XCTAssertEqual(settings.tips.dismissed, [.defectPhotos, .swipeDays])
        XCTAssertNil(settings.tip(for: .defects, facts: TipFacts(defectsAreEmpty: true)))

        settings.tips.showAllAgain()
        XCTAssertTrue(settings.tips.dismissed.isEmpty)
        XCTAssertEqual(settings.tip(for: .defects, facts: TipFacts(defectsAreEmpty: true)), .defectPhotos)
    }

    func testTheSwitchHidesEveryTip() {
        var settings = AppSettings()
        settings.tips.isEnabled = false
        XCTAssertNil(settings.tip(for: .defects, facts: TipFacts(defectsAreEmpty: true)))
    }

    /// Untouched, nothing is written, so settings without tips are written
    /// exactly as before.
    func testTheDefaultsAreNotWritten() throws {
        let json = String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self)
        XCTAssertFalse(json.contains("\"tips\""))
    }

    func testTheyRoundTripAndAreBackedUp() throws {
        var settings = AppSettings()
        settings.tips.isEnabled = false
        settings.tips.dismiss(.siteWorkDays)

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.tips, settings.tips)
        XCTAssertEqual(restored, settings)

        let back = try BackupArchive.decoded(from: BackupArchive(settings: settings, days: [], holidays: []).encoded())
        XCTAssertFalse(back.settings.tips.isEnabled)
        XCTAssertEqual(back.settings.tips.dismissed, [.siteWorkDays])
    }

    func testOlderOrUnreadableSettingsReadAsTheDefaults() throws {
        let older = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        XCTAssertEqual(older.tips, TipPreferences())

        let junk = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tips":7}"#.utf8))
        XCTAssertEqual(junk.tips, TipPreferences())

        let halfJunk = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"tips":{"isEnabled":"no","dismissed":["defectPhotos",3]}}"#.utf8)
        )
        XCTAssertTrue(halfJunk.tips.isEnabled)
        XCTAssertEqual(halfJunk.tips.dismissed, [.defectPhotos])
    }

    /// A tip a newer version dismissed is kept when this one writes the
    /// settings back, so syncing devices on two versions do not bring it
    /// back; "Show all tips again" clears it too.
    func testATipFromANewerVersionIsKept() throws {
        let json = #"{"tips":{"dismissed":["defectPhotos","somethingNew"]}}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.tips.dismissed, [.defectPhotos])

        let written = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertTrue(written.contains("somethingNew"))

        settings.tips.showAllAgain()
        XCTAssertTrue(settings.tips.isStandard)
    }
}
