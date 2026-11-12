import XCTest
@testable import Hours

/// The device client over a stub transport: the calls it makes, and the
/// protocol's errors sorted by what the app does about them.
final class ConnectClientTests: XCTestCase {
    private let device = ConnectV1.DeviceInfo(name: "Test phone", appVersion: "1.3")

    private func client(_ stub: ConnectTransport, token: String? = nil) -> ConnectClient {
        ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: token)
    }

    func testPairsByTypedCodeAndCallsTheModulesPath() async throws {
        let stub = ConnectStubTransport.sample()
        let paired = try await ConnectSession.pair(client: client(stub), code: "k7qf-3mzp", device: device, now: Date())
        XCTAssertEqual(paired.token, "zkd_stub")
        XCTAssertEqual(paired.account.companyName, "Beispiel Bau GmbH")
        XCTAssertEqual(paired.account.baseURL, "https://firm.example/api/zeitkonto")
        XCTAssertEqual(paired.state.people.you.map(ConnectID.string), "0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11")
        XCTAssertFalse(paired.state.people.youIsLocal)

        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://firm.example/api/zeitkonto/v1/device/pair")
        XCTAssertNil(request.headers["Authorization"], "pairing has no token")
        let body = try ConnectJSON.decode(ConnectV1.PairRequest.self, from: XCTUnwrap(request.body))
        XCTAssertEqual(body.code, "K7QF3MZP", "dashes and case are tidied before sending")
        XCTAssertEqual(body.device.appVersion, "1.3")
    }

    func testPairedWithoutAPersonYouGetsAnIdOfItsOwn() async throws {
        let stub = ConnectStubTransport(member: nil)
        let own = UUID()
        let paired = try await ConnectSession.pair(client: client(stub), code: ConnectStubTransport.code, device: device, now: Date(), newID: { own })
        XCTAssertEqual(paired.state.people.you, own)
        XCTAssertTrue(paired.state.people.youIsLocal)
    }

    func testAWrongCodeIsAPairingError() async {
        let stub = ConnectStubTransport.sample()
        do {
            _ = try await ConnectSession.pair(client: client(stub), code: "AAAABBBB", device: device, now: Date())
            XCTFail("a wrong code must not pair")
        } catch {
            XCTAssertEqual(error as? ConnectError, .pairingCodeInvalid)
        }
    }

    func testCallsCarryTheToken() async throws {
        let stub = ConnectStubTransport.sample()
        _ = try await ConnectSession.pair(client: client(stub), code: ConnectStubTransport.code, device: device, now: Date())
        _ = try await client(stub, token: "zkd_stub").sync(since: "c1.4")
        let sync = try XCTUnwrap(stub.requests.last)
        XCTAssertEqual(sync.headers["Authorization"], "Bearer zkd_stub")
        XCTAssertEqual(sync.url.absoluteString, "https://firm.example/api/zeitkonto/v1/device/sync?since=c1.4")
    }

    func testARevokedTokenIsDeviceRevoked() async throws {
        let stub = ConnectStubTransport.sample()
        _ = try await ConnectSession.pair(client: client(stub), code: ConnectStubTransport.code, device: device, now: Date())
        stub.revoke()
        do {
            _ = try await client(stub, token: "zkd_stub").me()
            XCTFail("a revoked token must fail")
        } catch {
            XCTAssertEqual(error as? ConnectError, .revoked)
            XCTAssertTrue((error as? ConnectError)?.disconnects == true)
        }
    }

    /// Each documented error code maps to what the app should do.
    func testErrorsByCode() throws {
        func error(_ status: Int, _ code: String, headers: [String: String] = [:]) -> ConnectError {
            let body = try! ConnectJSON.encode(ConnectV1.ErrorResponse(error: ConnectV1.ErrorBody(code: ConnectV1.ErrorCode(rawValue: code), message: "m")))
            return ConnectError.from(status: status, body: body, headers: headers)
        }
        XCTAssertEqual(error(401, "device_revoked"), .revoked)
        XCTAssertEqual(error(401, "unauthorized"), .unauthorized)
        XCTAssertEqual(error(400, "pairing_code_invalid"), .pairingCodeInvalid)
        XCTAssertEqual(error(410, "pairing_code_expired"), .pairingCodeExpired)
        XCTAssertEqual(error(410, "pairing_code_used"), .pairingCodeUsed)
        XCTAssertEqual(error(429, "rate_limited", headers: ["Retry-After": "30"]), .rateLimited(retryAfter: 30))
        XCTAssertEqual(error(413, "payload_too_large"), .payloadTooLarge)
        XCTAssertEqual(error(422, "validation_failed"), .validationFailed(message: "m"))
        XCTAssertEqual(error(500, "internal"), .server(status: 500))
        XCTAssertEqual(error(403, "forbidden"), .refused(status: 403, code: "forbidden", message: "m"))
        // The fixture for a revoked device.
        let fixture = try ConnectFixtures.data("error.unauthorized")
        XCTAssertEqual(ConnectError.from(status: 401, body: fixture, headers: [:]), .revoked)
        // A gateway's own page, not JSON.
        XCTAssertEqual(ConnectError.from(status: 502, body: Data("<html>".utf8), headers: [:]), .server(status: 502))

        XCTAssertTrue(ConnectError.offline.isRetryable)
        XCTAssertTrue(ConnectError.server(status: 503).isRetryable)
        XCTAssertTrue(ConnectError.rateLimited(retryAfter: nil).isRetryable)
        XCTAssertFalse(ConnectError.validationFailed(message: "").isRetryable)
        XCTAssertFalse(ConnectError.revoked.isRetryable)
    }

    func testNoAnswerIsOffline() async {
        let stub = ConnectStubTransport.sample()
        stub.plan([.failure(URLError(.notConnectedToInternet))])
        do {
            _ = try await client(stub, token: "zkd_stub").me()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? ConnectError, .offline)
        }
    }

    func testTheBaseURLKeepsItsPath() {
        let withSlash = ConnectClient(baseURL: URL(string: "https://firm.example/api/zeitkonto/")!, transport: ConnectStubTransport())
        XCTAssertEqual(withSlash.url(for: "v1/device/me")?.absoluteString, "https://firm.example/api/zeitkonto/v1/device/me")
    }
}
