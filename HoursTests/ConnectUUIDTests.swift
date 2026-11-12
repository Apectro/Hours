import XCTest
@testable import Hours

/// The name-based ids must be the server's to the byte: it refuses a site
/// day or a sign-off whose id is not `siteDayId` / `signOffId` of its key.
final class ConnectUUIDTests: XCTestCase {
    func testSHA1KnownAnswers() {
        XCTAssertEqual(ConnectUUID.digest(Data()), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(ConnectUUID.digest(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        // Two blocks: the padding crosses a block boundary.
        XCTAssertEqual(
            ConnectUUID.digest(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        )
    }

    /// RFC 9562's own example: "www.example.com" in the DNS namespace.
    func testVersion5KnownAnswer() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        XCTAssertEqual(
            ConnectUUID.v5("www.example.com", namespace: dns).uuidString.lowercased(),
            "2ed6657d-e927-568b-95e1-2665a8aea6a2"
        )
    }

    /// Every site day in the October fixture carries the id the server
    /// computes from its site and date.
    func testSiteDayIDsMatchTheFixtures() throws {
        let days = try ConnectFixtures.decode([ConnectV1.SiteDay].self, "october.site-days")
        XCTAssertFalse(days.isEmpty)
        for day in days {
            let siteID = try XCTUnwrap(UUID(uuidString: day.siteId))
            let date = try XCTUnwrap(ConnectFormat.parseDate(day.date))
            XCTAssertEqual(ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: date)), day.id, "\(day.siteId) \(day.date)")
        }
    }

    func testSignOffIDMatchesTheFixture() throws {
        let request = try ConnectFixtures.decode(ConnectV1.UploadRequest.self, "device.upload.request")
        let signOffs = try request.records.filter { $0.kind == .signOff }.compactMap { try $0.decodedData(as: ConnectV1.SignOff.self) }
        XCTAssertEqual(signOffs.count, 1)
        for signOff in signOffs {
            let id = ConnectUUID.signOffID(
                siteID: try XCTUnwrap(UUID(uuidString: signOff.siteId)),
                memberID: try XCTUnwrap(UUID(uuidString: signOff.memberId)),
                month: try XCTUnwrap(ConnectFormat.parseMonth(signOff.month))
            )
            XCTAssertEqual(ConnectID.string(id), signOff.id)
        }
    }

    /// The app prints UUIDs in upper case; the key is lower case either way.
    func testCaseOfTheSiteIDDoesNotMatter() {
        let upper = UUID(uuidString: "A2364FC3-F9D6-51DC-9EB9-41868669E10F")!
        let date = CalendarDate(year: 2026, month: 10, day: 1)
        XCTAssertEqual(ConnectID.string(ConnectUUID.siteDayID(siteID: upper, date: date)), "77593f12-e0f2-556b-af9a-7fadea4eb5df")
    }

    func testFormats() {
        XCTAssertEqual(ConnectFormat.date(CalendarDate(year: 2026, month: 3, day: 7)), "2026-03-07")
        XCTAssertEqual(ConnectFormat.month(YearMonth(year: 2026, month: 3)), "2026-03")
        XCTAssertEqual(ConnectFormat.time(TimeOfDay(hour: 7, minute: 5)), "07:05")
        XCTAssertEqual(ConnectFormat.parseTime("23:59"), TimeOfDay(hour: 23, minute: 59))
        XCTAssertNil(ConnectFormat.parseTime("24:00"))
        XCTAssertEqual(ConnectFormat.quantity(Decimal(string: "45.5")!), "45.5")
        XCTAssertEqual(ConnectFormat.quantity(Decimal(12)), "12")
        XCTAssertEqual(ConnectFormat.quantity(Decimal(string: "1.23456")!), "1.235")
        XCTAssertEqual(ConnectFormat.moment(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00Z")
        XCTAssertEqual(ConnectFormat.parseMoment("2026-11-02T09:30:00Z"), Date(timeIntervalSince1970: 1_793_611_800))
    }
}
