import XCTest
@testable import Hours

final class SiteAccessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let pro = Entitlement(kind: .lifetime, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private func site(_ order: Int, archived: Bool = false, id: UUID = UUID()) -> Site {
        Site(id: id, name: "Site \(order)", isArchived: archived, sortOrder: order)
    }

    // MARK: - Adding

    func testFirstSiteIsFree() {
        XCTAssertTrue(SiteAccess.canAddSite(activeSites: 0, entitlement: .free, at: now))
    }

    func testSecondSiteNeedsPro() {
        XCTAssertFalse(SiteAccess.canAddSite(activeSites: 1, entitlement: .free, at: now))
        XCTAssertTrue(SiteAccess.canAddSite(activeSites: 1, entitlement: pro, at: now))
        XCTAssertTrue(SiteAccess.canAddSite(activeSites: 5, entitlement: pro, at: now))
    }

    // MARK: - Read-only

    func testLapsedProKeepsFirstSiteWritableOthersReadOnly() {
        let first = site(0), second = site(1), third = site(2)
        let active = [third, first, second]

        XCTAssertFalse(SiteAccess.isReadOnly(first, activeSites: active, entitlement: .free, at: now))
        XCTAssertTrue(SiteAccess.isReadOnly(second, activeSites: active, entitlement: .free, at: now))
        XCTAssertTrue(SiteAccess.isReadOnly(third, activeSites: active, entitlement: .free, at: now))

        for each in active {
            XCTAssertFalse(SiteAccess.isReadOnly(each, activeSites: active, entitlement: pro, at: now))
        }
    }

    func testTiesBreakByIdentifier() {
        let low = site(0, id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
        let high = site(0, id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)

        XCTAssertFalse(SiteAccess.isReadOnly(low, activeSites: [high, low], entitlement: .free, at: now))
        XCTAssertTrue(SiteAccess.isReadOnly(high, activeSites: [low, high], entitlement: .free, at: now))
    }

    func testArchivedSitesDoNotCount() {
        let archived = site(0, archived: true)
        let live = site(1)

        // The archived one has the lowest order but is not active, so the live
        // one is the free site.
        XCTAssertFalse(SiteAccess.isReadOnly(live, activeSites: [live], entitlement: .free, at: now))
        XCTAssertTrue(SiteAccess.isReadOnly(archived, activeSites: [live], entitlement: .free, at: now))
        XCTAssertFalse(SiteAccess.isReadOnly(archived, activeSites: [live], entitlement: pro, at: now))
    }

    func testAlwaysFreeListUnchanged() {
        XCTAssertEqual(ProFeature.alwaysFree, [
            "Recording and editing your hours",
            "The calendar, the balance and every total",
            "Reminders about days you have not filled in",
            "The backup file, which holds everything you ever recorded",
        ])
    }

    func testMultipleSitesExplainsItself() {
        XCTAssertFalse(ProFeature.multipleSites.title.isEmpty)
        XCTAssertFalse(ProFeature.multipleSites.explanation.isEmpty)
        XCTAssertEqual(ProFeature.multipleSites.symbolName, "building.2")
    }

    // MARK: - Backup

    func testOldBackupDecodesWithNilSites() throws {
        let old = BackupArchive(settings: AppSettings(), days: [], holidays: [])
        let data = try old.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"sites\""))
        XCTAssertFalse(text.contains("\"crew\""))
        XCTAssertFalse(text.contains("\"siteDays\""))

        let decoded = try BackupArchive.decoded(from: data)
        XCTAssertNil(decoded.sites)
        XCTAssertNil(decoded.crew)
        XCTAssertNil(decoded.siteDays)
        XCTAssertEqual(BackupArchive.currentFormatVersion, 1)
    }

    func testBackupRoundTripsSites() throws {
        let s = site(0)
        let member = CrewMember(siteID: s.id, name: "Ana")
        let day = SiteDay(siteID: s.id, date: CalendarDate(year: 2026, month: 10, day: 20), note: "Poured slab")
        let archive = BackupArchive(
            settings: AppSettings(), days: [], holidays: [],
            sites: [s], crew: [member], siteDays: [day]
        )

        let decoded = try BackupArchive.decoded(from: try archive.encoded())

        XCTAssertEqual(decoded.sites, [s])
        XCTAssertEqual(decoded.crew, [member])
        XCTAssertEqual(decoded.siteDays, [day])
    }

    func testEmptyButPresentSitesStayDistinctFromAbsent() throws {
        let archive = BackupArchive(settings: AppSettings(), days: [], holidays: [], sites: [], crew: [], siteDays: [])
        let decoded = try BackupArchive.decoded(from: try archive.encoded())
        XCTAssertEqual(decoded.sites, [])
        XCTAssertEqual(decoded.siteDays, [])
    }
}
