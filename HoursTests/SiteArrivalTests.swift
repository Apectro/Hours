import XCTest
@testable import Hours

/// Where a site is, for the opt-in arrival reminder (1.2): kept on the site,
/// written into a backup only when set, and read back by every decoder.
final class SiteArrivalTests: XCTestCase {
    private func placed(_ name: String = "Trg Pravde", radius: Double = 300, reminds: Bool = true) -> Site {
        var site = Site(name: name)
        site.place = SitePlace(latitude: 45.8150, longitude: 15.9819)
        site.arrivalRadius = radius
        site.remindsOnArrival = reminds
        return site
    }

    // MARK: - The site

    func testANewSiteHasNoPlaceAndNoReminder() {
        let site = Site(name: "Bau Süd")
        XCTAssertNil(site.place)
        XCTAssertNil(site.latitude)
        XCTAssertNil(site.longitude)
        XCTAssertEqual(site.arrivalRadius, 150)
        XCTAssertFalse(site.remindsOnArrival)
        XCTAssertFalse(site.monitorsArrival)
    }

    func testThePlaceNeedsBothCoordinates() {
        var site = Site(name: "Bau Süd")
        site.latitude = 45.8
        XCTAssertNil(site.place, "half a coordinate is no place")
        site.longitude = 15.9
        XCTAssertEqual(site.place, SitePlace(latitude: 45.8, longitude: 15.9))
        site.place = nil
        XCTAssertNil(site.latitude)
        XCTAssertNil(site.longitude)
    }

    func testACoordinateOffTheGlobeIsNoPlace() {
        var site = Site(name: "Bau Süd")
        site.latitude = 91
        site.longitude = 15
        XCTAssertNil(site.place)
        site.latitude = 45
        site.longitude = -181
        XCTAssertNil(site.place)
        site.latitude = .nan
        site.longitude = 15
        XCTAssertNil(site.place)
    }

    func testOnlyAnActiveSiteWithAPlaceAndTheSwitchOnIsWatched() {
        XCTAssertTrue(placed().monitorsArrival)
        XCTAssertFalse(placed(reminds: false).monitorsArrival)
        var archived = placed()
        archived.isArchived = true
        XCTAssertFalse(archived.monitorsArrival)
        var nowhere = placed()
        nowhere.place = nil
        XCTAssertFalse(nowhere.monitorsArrival, "the switch alone, with no place, watches nothing")
    }

    func testTheRadiusChoicesAndAnOddStoredRadius() {
        XCTAssertEqual(Site.arrivalRadii, [100, 150, 300, 500])
        XCTAssertEqual(placed(radius: 300).monitoredRadius, 300)
        XCTAssertEqual(placed(radius: 0).monitoredRadius, 150, "no radius is the default")
        XCTAssertEqual(placed(radius: -20).monitoredRadius, 150)
        XCTAssertEqual(placed(radius: 5).monitoredRadius, 100, "never tighter than the smallest choice")
        XCTAssertEqual(placed(radius: 50_000).monitoredRadius, 500, "never wider than the largest choice")
    }

    // MARK: - Coding

    func testASiteWithAPlaceRoundTrips() throws {
        let site = placed()
        let decoded = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        XCTAssertEqual(decoded, site)
        XCTAssertEqual(decoded.place, site.place)
        XCTAssertEqual(decoded.arrivalRadius, 300)
        XCTAssertTrue(decoded.remindsOnArrival)
    }

    func testASiteWithoutAPlaceIsWrittenExactlyAsBefore() throws {
        let data = try JSONEncoder().encode(Site(name: "Bau Süd"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "name", "isArchived", "sortOrder"])
    }

    func testAnOlderSiteReadsAsNoPlace() throws {
        let old = try JSONDecoder().decode(
            Site.self,
            from: Data(#"{"name": "Old", "isArchived": false, "sortOrder": 0}"#.utf8)
        )
        XCTAssertNil(old.place)
        XCTAssertEqual(old.arrivalRadius, 150)
        XCTAssertFalse(old.remindsOnArrival)
    }

    func testAnUnreadableArrivalKeyLosesOnlyItself() throws {
        let json = #"{"name": "Odd", "isArchived": false, "sortOrder": 0, "latitude": "north", "longitude": 15.9, "arrivalRadius": 300, "remindsOnArrival": true}"#
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        XCTAssertEqual(site.name, "Odd")
        XCTAssertNil(site.place)
        XCTAssertEqual(site.arrivalRadius, 300)
        XCTAssertTrue(site.remindsOnArrival)
    }

    // MARK: - Backups

    private func backup() -> BackupArchive {
        BackupArchive(
            exportedAt: Date(timeIntervalSince1970: 1_792_000_000),
            settings: Fixture.settings(),
            days: [],
            holidays: [],
            sites: [placed(), Site(name: "Schulweg 4", sortOrder: 1)],
            crew: [],
            siteDays: []
        )
    }

    func testABackupRoundTripsTheSitesPlaceRadiusAndSwitch() throws {
        let original = backup()
        let restored = try BackupArchive.decoded(from: original.encoded())
        XCTAssertEqual(restored.sites, original.sites)
        XCTAssertEqual(restored.sites?.first?.place, SitePlace(latitude: 45.8150, longitude: 15.9819))
        XCTAssertEqual(restored.sites?.first?.arrivalRadius, 300)
        XCTAssertEqual(restored.sites?.first?.remindsOnArrival, true)
        XCTAssertNil(restored.sites?.last?.place)
    }

    /// What 1.0 and 1.1 read of a 1.2 backup: their site is where it was,
    /// and the new keys beside it are skipped.
    func testAnOlderAppStillReadsTheSites() throws {
        struct OldArchive: Decodable {
            struct Site: Decodable {
                var id: UUID
                var name: String
                var isArchived: Bool
                var sortOrder: Int
            }
            var formatVersion: Int
            var sites: [Site]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(OldArchive.self, from: backup().encoded())
        XCTAssertEqual(old.formatVersion, 1)
        XCTAssertEqual(old.sites.map(\.name), ["Trg Pravde", "Schulweg 4"])
    }

    func testABackupFromBeforeRestoresSitesWithNoPlace() throws {
        let data = try backup().encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["sites"] = (json["sites"] as? [[String: Any]])?.map { site in
            site.filter { !["latitude", "longitude", "arrivalRadius", "remindsOnArrival"].contains($0.key) }
        }
        let restored = try BackupArchive.decoded(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.sites?.count, 2)
        XCTAssertTrue(restored.sites?.allSatisfy { $0.place == nil && !$0.remindsOnArrival } ?? false)
    }
}
