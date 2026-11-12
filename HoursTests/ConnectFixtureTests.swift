import XCTest
@testable import Hours

/// The Connect protocol's example payloads (`packages/protocol/fixtures/v1`
/// in the Connect repository, copied into `Fixtures/ConnectV1`): every one
/// decodes into the app's wire types, and encoding it again says everything
/// the fixture said. The server's own tests decode the same files, so the
/// two sides cannot drift apart without one of them going red.
final class ConnectFixtureTests: XCTestCase {
    typealias V1 = ConnectV1

    /// Every fixture and the type it is. A new fixture fails the suite until
    /// it is added here.
    private static let types: [String: (Data) throws -> (decoded: AnyHashable, reencoded: Data)] = [
        "device.files.request": check(V1.FileUploadRequest.self),
        "device.files.response": check(V1.FileUploadResponse.self),
        "device.me.response": check(V1.MeResponse.self),
        "device.pair.request": check(V1.PairRequest.self),
        "device.pair.response": check(V1.PairResponse.self),
        "device.sync.response": check(V1.SyncResponse.self),
        "device.unpair.response": check(V1.OkResponse.self),
        "device.upload.request": check(V1.UploadRequest.self),
        "device.upload.response": check(V1.UploadResponse.self),
        "error.unauthorized": check(V1.ErrorResponse.self),
        "error.validation": check(V1.ErrorResponse.self),
        "october.month-sheet": check(V1.MonthSheet.self),
        "october.site-days": check([V1.SiteDay].self),
        "pairing-qr": check(V1.PairingQr.self),
        "admin.assignments.create.request": check(V1.AssignmentInput.self),
        "admin.assignments.create.response": check(V1.Assignment.self),
        "admin.assignments.delete.response": check(V1.OkResponse.self),
        "admin.assignments.list.response": check(V1.ListOf<V1.Assignment>.self),
        "admin.assignments.patch.request": check(V1.AssignmentPatch.self),
        "admin.assignments.patch.response": check(V1.Assignment.self),
        "admin.comments.create.request": check(V1.CommentRequest.self),
        "admin.comments.create.response": check(V1.CommentResponse.self),
        "admin.comments.list.response": check(V1.ListOf<V1.Comment>.self),
        "admin.company.get.response": check(V1.CompanyResponse.self),
        "admin.company.patch.request": check(V1.CompanyPatch.self),
        "admin.company.patch.response": check(V1.CompanyResponse.self),
        "admin.crew.create.request": check(V1.CrewMemberInput.self),
        "admin.crew.create.response": check(V1.CrewMember.self),
        "admin.crew.delete.response": check(V1.OkResponse.self),
        "admin.crew.erase.response": check(V1.OkResponse.self),
        "admin.crew.get.response": check(V1.CrewMember.self),
        "admin.crew.list.response": check(V1.ListOf<V1.CrewMember>.self),
        "admin.crew.patch.request": check(V1.CrewMemberPatch.self),
        "admin.crew.patch.response": check(V1.CrewMember.self),
        "admin.defects.list.response": check(V1.ListOf<V1.OfficeView<V1.Defect>>.self),
        "admin.defects.patch.request": check(V1.StatePatch.self),
        "admin.defects.patch.response": check(V1.OfficeView<V1.Defect>.self),
        "admin.deliveries.list.response": check(V1.ListOf<V1.OfficeView<V1.Delivery>>.self),
        "admin.devices.list.response": check(V1.ListOf<V1.Device>.self),
        "admin.devices.revoke.response": check(V1.OkResponse.self),
        "admin.export.response": check(V1.CompanyExport.self),
        "admin.extraWork.list.response": check(V1.ListOf<V1.OfficeView<V1.ExtraWork>>.self),
        "admin.extraWork.patch.request": check(V1.StatePatch.self),
        "admin.extraWork.patch.response": check(V1.OfficeView<V1.ExtraWork>.self),
        "admin.files.get.response": check(V1.FileDownloadResponse.self),
        "admin.hours.response": check(V1.MonthHours.self),
        "admin.missing.list.response": check(V1.ListOf<V1.OfficeView<V1.MissingItem>>.self),
        "admin.missing.patch.request": check(V1.StatePatch.self),
        "admin.missing.patch.response": check(V1.OfficeView<V1.MissingItem>.self),
        "admin.pairing.create.request": check(V1.PairingCodeRequest.self),
        "admin.pairing.create.response": check(V1.PairingCodeResponse.self),
        "admin.pairing.list.response": check(V1.ListOf<V1.PairingCodeSummary>.self),
        "admin.pairing.revoke.response": check(V1.OkResponse.self),
        "admin.sheets.approve.response": check(V1.Sheet.self),
        "admin.sheets.get.response": check(V1.Sheet.self),
        "admin.sheets.list.response": check(V1.ListOf<V1.SheetSummary>.self),
        "admin.sheets.return.request": check(V1.ReturnRequest.self),
        "admin.sheets.return.response": check(V1.Sheet.self),
        "admin.signOffs.list.response": check(V1.ListOf<V1.OfficeView<V1.SignOff>>.self),
        "admin.siteDays.list.response": check(V1.ListOf<V1.OfficeView<V1.SiteDay>>.self),
        "admin.sites.create.request": check(V1.SiteInput.self),
        "admin.sites.create.response": check(V1.Site.self),
        "admin.sites.delete.response": check(V1.OkResponse.self),
        "admin.sites.get.response": check(V1.Site.self),
        "admin.sites.list.response": check(V1.ListOf<V1.Site>.self),
        "admin.sites.patch.request": check(V1.SitePatch.self),
        "admin.sites.patch.response": check(V1.Site.self),
    ]

    private static func check<T: Codable & Hashable>(_ type: T.Type) -> (Data) throws -> (decoded: AnyHashable, reencoded: Data) {
        { data in
            let decoded = try ConnectJSON.decode(T.self, from: data)
            let reencoded = try ConnectJSON.encode(decoded)
            let again = try ConnectJSON.decode(T.self, from: reencoded)
            XCTAssertEqual(decoded, again, "\(T.self) does not survive a round trip")
            return (AnyHashable(decoded), reencoded)
        }
    }

    func testEveryFixtureIsChecked() throws {
        let names = Set(try ConnectFixtures.names())
        XCTAssertFalse(names.isEmpty, "no fixtures found in \(ConnectFixtures.folder.path)")
        XCTAssertEqual(names.subtracting(Self.types.keys).sorted(), [], "fixtures with no type to decode them")
        XCTAssertEqual(Set(Self.types.keys).subtracting(names).sorted(), [], "types listed for fixtures that are gone")
    }

    func testEveryFixtureDecodesAndEncodesBack() throws {
        for name in try ConnectFixtures.names().sorted() {
            guard let check = Self.types[name] else { continue }
            let data = try ConnectFixtures.data(name)
            do {
                let (_, reencoded) = try check(data)
                let original = try ConnectJSON.decode(JSONValue.self, from: data)
                let written = try ConnectJSON.decode(JSONValue.self, from: reencoded)
                XCTAssertTrue(original.isContained(in: written), "\(name): encoding it again lost or changed something")
            } catch {
                XCTFail("\(name) does not decode: \(error)")
            }
        }
    }

    /// Each record of the example batch decodes as its own kind's type.
    func testUploadRecordsDecodeByKind() throws {
        let request = try ConnectJSON.decode(V1.UploadRequest.self, from: ConnectFixtures.data("device.upload.request"))
        XCTAssertEqual(request.records.count, 9)
        for record in request.records {
            switch record.kind {
            case .siteDay: XCTAssertNotNil(try record.decodedData(as: V1.SiteDay.self))
            case .sheet: XCTAssertNotNil(try record.decodedData(as: V1.MonthSheet.self))
            case .signOff: XCTAssertNotNil(try record.decodedData(as: V1.SignOff.self))
            case .extraWork: XCTAssertNotNil(try record.decodedData(as: V1.ExtraWork.self))
            case .defect: XCTAssertNotNil(try record.decodedData(as: V1.Defect.self))
            case .missingItem: XCTAssertNotNil(try record.decodedData(as: V1.MissingItem.self))
            case .delivery: XCTAssertNotNil(try record.decodedData(as: V1.Delivery.self))
            default: XCTFail("unexpected kind \(record.kind.rawValue)")
            }
        }
    }

    /// A newer server may add fields and words: they are ignored or kept,
    /// never a failure.
    func testUnknownFieldsAndWordsAreIgnored() throws {
        let json = """
        {"kind":"siteDay","id":"77593f12-e0f2-556b-af9a-7fadea4eb5df","status":"queuedForLater","version":4,
         "somethingNew":{"a":1},"reason":"aNewReason"}
        """
        let result = try ConnectJSON.decode(V1.UploadResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.status.rawValue, "queuedForLater")
        XCTAssertEqual(result.reason, "aNewReason")
        XCTAssertEqual(result.version, 4)

        let day = try ConnectJSON.decode(V1.SiteDay.self, from: Data("""
        {"id":"x","siteId":"y","date":"2026-10-01","updatedAt":"2026-10-01T15:45:00Z","colour":"teal","breakMinutes":null}
        """.utf8))
        XCTAssertEqual(day.breakMinutes, 0, "a missing or null default takes the default")
        XCTAssertEqual(day.attendance, [])
        XCTAssertFalse(day.badWeatherStop)
    }

    func testTheQRCodeReads() throws {
        let text = String(decoding: try ConnectFixtures.data("pairing-qr"), as: UTF8.self)
        let read = try ConnectPairing.parseQR(text)
        XCTAssertEqual(read.url.absoluteString, "https://firm.example/api/zeitkonto")
        XCTAssertEqual(read.code, "K7QF3MZP")

        XCTAssertThrowsError(try ConnectPairing.parseQR(#"{"v":2,"url":"https://firm.example/api/zeitkonto","code":"K7QF3MZP"}"#)) { error in
            XCTAssertEqual(error as? ConnectError, .unsupportedVersion, "a v other than 1 means: update the app")
        }
        XCTAssertThrowsError(try ConnectPairing.parseQR("not json"))
    }

    func testCodesAndAddressesAsTyped() {
        XCTAssertEqual(ConnectPairing.normalizedCode("k7qf-3mzp"), "K7QF3MZP")
        XCTAssertEqual(ConnectPairing.normalizedCode(" K7QF 3MZP "), "K7QF3MZP")
        XCTAssertNil(ConnectPairing.normalizedCode("K7QF3MZ"))
        XCTAssertEqual(ConnectPairing.address("firm.example/api/zeitkonto")?.absoluteString, "https://firm.example/api/zeitkonto")
        XCTAssertNil(ConnectPairing.address("http://firm.example"), "plain http only to a machine on the desk")
        XCTAssertNotNil(ConnectPairing.address("http://localhost:3000/api/zeitkonto"))
        XCTAssertNil(ConnectPairing.address(""))
        XCTAssertEqual(ConnectPairing.host(of: URL(string: "https://www.firm.example/api")!), "firm.example")
    }
}

/// The fixture files, read from beside this source file: the same path
/// works under `swift test` and in the app's test bundle on the simulator.
enum ConnectFixtures {
    static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("ConnectV1")
    }

    static func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
    }

    static func data(_ name: String) throws -> Data {
        let file = folder.appendingPathComponent(name + ".json")
        if let data = try? Data(contentsOf: file) { return data }
        // In a bundle, should the source tree not be reachable.
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: "json") {
                return try Data(contentsOf: url)
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try ConnectJSON.decode(T.self, from: data(name))
    }
}
