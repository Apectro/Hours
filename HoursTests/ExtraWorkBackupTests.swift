import XCTest
@testable import Hours

/// Extra work in a backup: jobs, their photos, the reports that were sent,
/// and the remembered items — and backups on either side of it.
final class ExtraWorkBackupTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let moment = Date(timeIntervalSince1970: 1_792_000_000)

    private var job: ExtraWorkJob {
        ExtraWorkJob(
            id: UUID(uuidString: "6F9E2A1C-0000-4000-8000-000000000001")!,
            siteID: site.id,
            date: Fixture.date(2026, 10, 22),
            description: "Emergency lighting, stairwell",
            items: [
                ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces),
                ExtraWorkItem(name: "Cable", quantity: Decimal(string: "12.5")!, unit: .metres)
            ],
            hours: [ExtraWorkHours(memberID: CrewMember.youID, name: "Marijo", minutes: 90)],
            clientSignature: ExtraWorkSignature(signerName: "Ing. Horvat", signedAt: moment, strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]),
            status: .sent,
            sentAt: moment,
            sentReportID: UUID(),
            createdAt: moment,
            updatedAt: moment
        )
    }

    private func archive() -> BackupArchive {
        var archive = BackupArchive(
            exportedAt: moment,
            settings: AppSettings(),
            days: [],
            holidays: [],
            sites: [site],
            crew: [],
            siteDays: []
        )
        archive.extraWorkJobs = [job]
        archive.extraWorkPhotos = [ExtraWorkPhoto(jobID: job.id, siteID: site.id, sortOrder: 0, jpegData: Data([0xFF, 0xD8, 0x07, 0xFF, 0xD9]))]
        archive.extraWorkReports = [ExtraWorkReportRecord(siteID: site.id, sentAt: moment, jobIDs: [job.id])]
        archive.extraWorkItems = [ExtraWorkCatalogItem(name: "Emergency light", unit: .pieces, useCount: 3, lastUsed: moment)]
        return archive
    }

    func testJobsPhotosReportsAndItemsRoundTrip() throws {
        let original = archive()
        let decoded = try BackupArchive.decoded(from: original.encoded())
        XCTAssertEqual(decoded.extraWorkJobs, original.extraWorkJobs)
        XCTAssertEqual(decoded.extraWorkPhotos, original.extraWorkPhotos)
        XCTAssertEqual(decoded.extraWorkReports, original.extraWorkReports)
        XCTAssertEqual(decoded.extraWorkItems, original.extraWorkItems)
    }

    func testPhotosAreBase64AndQuantitiesAreText() throws {
        let text = String(decoding: try archive().encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(Data([0xFF, 0xD8, 0x07, 0xFF, 0xD9]).base64EncodedString()))
        XCTAssertTrue(text.contains(#""quantity" : "12.5""#), "exact on every platform")
    }

    func testTheFormatVersionStaysOne() throws {
        XCTAssertEqual(try BackupArchive.decoded(from: archive().encoded()).formatVersion, 1)
    }

    func testABackupWithoutExtraWorkWritesNoneOfItsKeys() throws {
        let plain = BackupArchive(settings: AppSettings(), days: [], holidays: [])
        let text = String(decoding: try plain.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("extraWork"))
    }

    /// A backup from 1.0 or from 1.1 before extra work: none of the lists.
    func testAnOlderBackupReadsAsHavingNone() throws {
        let json = """
        {"formatVersion": 1, "exportedAt": "2026-10-01T08:00:00Z", "settings": {}, "days": [], "holidays": [],
         "sites": [{"id": "\(site.id.uuidString)", "name": "Trg Pravde Zagreb"}], "crew": [], "siteDays": []}
        """
        let decoded = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertNil(decoded.extraWorkJobs)
        XCTAssertNil(decoded.extraWorkPhotos)
        XCTAssertNil(decoded.extraWorkReports)
        XCTAssertNil(decoded.extraWorkItems)
    }

    func testADamagedListCostsThatListNotTheBackup() throws {
        let json = """
        {"formatVersion": 1, "settings": {}, "days": [], "holidays": [], "extraWorkJobs": {"not": "a list"}}
        """
        XCTAssertNil(try BackupArchive.decoded(from: Data(json.utf8)).extraWorkJobs)
    }

    /// The shape 1.0 decodes a backup with: its own keys, synthesised, and
    /// nothing else. Keys it does not know are skipped, and the format
    /// version 1.1 writes is one it accepts — so a 1.1 backup with extra
    /// work restores on 1.0 with its hours, sites and diary-less site days.
    private struct VersionOneArchive: Decodable {
        var formatVersion: Int
        var exportedAt: Date
        var days: [DayRecord]
        var holidays: [HolidayRule]
        var sites: [Site]?
        var crew: [CrewMember]?
        var siteDays: [SiteDay]?
    }

    func testOnePointZeroStillReadsABackupWithExtraWork() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(VersionOneArchive.self, from: archive().encoded())
        XCTAssertLessThanOrEqual(old.formatVersion, 1, "1.0 refuses anything newer than 1")
        XCTAssertEqual(old.sites?.map(\.id), [site.id])
    }

    /// A file that carries extra work replaces the device's; one from before
    /// keeps the device's for the sites it restores. The remembered items
    /// belong to nobody's site: an older file keeps the device's.
    func testWhatARestoreKeeps() {
        let kept = Site(name: "Kept")
        let gone = Site(name: "Gone")
        let onPhone = [
            ExtraWorkJob(siteID: kept.id, date: Fixture.date(2026, 10, 1), description: "a"),
            ExtraWorkJob(siteID: gone.id, date: Fixture.date(2026, 10, 1), description: "b")
        ]
        XCTAssertEqual(
            BackupArchive.restoredItems(fromFile: nil, onDevice: onPhone, restoredSiteIDs: [kept.id], siteID: \.siteID),
            [onPhone[0]]
        )
        let items = [ExtraWorkCatalogItem(name: "Lamp", unit: .pieces)]
        XCTAssertEqual(BackupArchive.restoredCatalog(fromFile: nil, onDevice: items), items)
        XCTAssertEqual(BackupArchive.restoredCatalog(fromFile: [], onDevice: items), [])
    }
}
