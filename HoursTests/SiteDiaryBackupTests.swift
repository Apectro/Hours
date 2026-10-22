import XCTest
@testable import Hours

/// The diary, its photos and the crew's signatures in a backup, and backups
/// from before they existed.
final class SiteDiaryBackupTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let date = Fixture.workingTuesday

    private func archive() -> BackupArchive {
        BackupArchive(
            exportedAt: Date(timeIntervalSince1970: 1_790_000_000),
            settings: AppSettings(),
            days: [],
            holidays: [],
            sites: [site],
            crew: [],
            siteDays: [SiteDay(siteID: site.id, date: date, isBadWeatherStop: true)],
            diaries: [SiteDiary(siteID: site.id, date: date, weather: .snow, temperatureCelsius: -2, workDone: "Gritting")],
            diaryPhotos: [DiaryPhoto(siteID: site.id, date: date, sortOrder: 0, jpegData: Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]))],
            signatures: [CrewSignature(
                siteID: site.id,
                memberID: CrewMember.youID,
                month: date.yearMonth,
                signedOn: Fixture.date(2026, 8, 31),
                fingerprint: "v1:0123456789abcdef",
                strokes: [[SignaturePoint(x: 0.1, y: 0.2), SignaturePoint(x: 2.5, y: 0.8)]]
            )]
        )
    }

    func testTheDiaryPhotosAndSignaturesRoundTrip() throws {
        let original = archive()
        let decoded = try BackupArchive.decoded(from: original.encoded())
        XCTAssertEqual(decoded.diaries, original.diaries)
        XCTAssertEqual(decoded.diaryPhotos, original.diaryPhotos)
        XCTAssertEqual(decoded.signatures, original.signatures)
        XCTAssertEqual(decoded.siteDays?.first?.isBadWeatherStop, true)
    }

    func testPhotosAreWrittenAsBase64InTheJSON() throws {
        let text = String(decoding: try archive().encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(Data([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]).base64EncodedString()))
    }

    func testTheFormatVersionDoesNotChangeSoOlderAppsStillReadTheFile() throws {
        XCTAssertEqual(BackupArchive.currentFormatVersion, 1)
        XCTAssertEqual(archive().formatVersion, 1)
    }

    /// A file from 1.0, with sites but none of the 1.1 lists.
    func testABackupFromBeforeTheDiaryStillRestores() throws {
        let json = """
        {
          "formatVersion": 1,
          "exportedAt": "2026-10-01T08:00:00Z",
          "settings": {},
          "days": [],
          "holidays": [],
          "sites": [{"id": "\(site.id.uuidString)", "name": "Bau Süd"}],
          "crew": [],
          "siteDays": [{"siteID": "\(site.id.uuidString)", "date": 20260804, "start": 420, "end": 960,
                        "breakMinutes": 30, "present": [], "note": ""}]
        }
        """
        let decoded = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertEqual(decoded.sites?.count, 1)
        XCTAssertEqual(decoded.siteDays?.first?.isBadWeatherStop, false)
        XCTAssertNil(decoded.diaries)
        XCTAssertNil(decoded.diaryPhotos)
        XCTAssertNil(decoded.signatures)
    }

    func testABackupWithoutTheListsWritesNoneOfThem() throws {
        let plain = BackupArchive(settings: AppSettings(), days: [], holidays: [])
        let text = String(decoding: try plain.encoded(), as: UTF8.self)
        XCTAssertFalse(text.contains("diaries"))
        XCTAssertFalse(text.contains("diaryPhotos"))
        XCTAssertFalse(text.contains("signatures"))
    }

    /// Damage in a list that is new in 1.1 must not cost the hours: the list
    /// reads as absent, like a damaged list of sites.
    func testADamagedDiaryListDoesNotRefuseTheBackup() throws {
        let json = """
        {"formatVersion": 1, "settings": {}, "days": [], "holidays": [], "diaries": "not a list"}
        """
        let decoded = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertNil(decoded.diaries)
    }

    /// What restoring a file means for the diaries already on the phone.
    func testWhatARestoreKeeps() {
        let kept = Site(name: "Kept")
        let gone = Site(name: "Gone")
        let onPhone = [
            SiteDiary(siteID: kept.id, date: date, workDone: "a"),
            SiteDiary(siteID: gone.id, date: date, workDone: "b")
        ]
        // A file that carries diaries replaces them.
        let fromFile = [SiteDiary(siteID: kept.id, date: date, workDone: "c")]
        XCTAssertEqual(BackupArchive.restoredItems(fromFile: fromFile, onDevice: onPhone, restoredSiteIDs: [kept.id], siteID: \.siteID), fromFile)
        // A file from before diaries keeps those whose site it restores, and
        // drops those whose site is gone.
        XCTAssertEqual(
            BackupArchive.restoredItems(fromFile: nil, onDevice: onPhone, restoredSiteIDs: [kept.id], siteID: \.siteID),
            [onPhone[0]]
        )
        // A file with no site data at all leaves everything as it was.
        XCTAssertEqual(
            BackupArchive.restoredItems(fromFile: nil, onDevice: onPhone, restoredSiteIDs: nil, siteID: \.siteID),
            onPhone
        )
    }
}
