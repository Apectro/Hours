import Foundation

/// One HTTP exchange, as plain values, so the client can be driven by
/// URLSession in the app and by a stub in the tests and the UI tests.
struct ConnectHTTPRequest: Hashable, Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data?
}

struct ConnectHTTPResponse: Hashable, Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data

    /// A header, by its name in any case.
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

/// What carries a request. `URLSessionConnectTransport` in the app; a stub
/// in the tests. Throws only when nothing came back (offline, a timeout).
protocol ConnectTransport: Sendable {
    func send(_ request: ConnectHTTPRequest) async throws -> ConnectHTTPResponse
}

/// Everything that can go wrong talking to the company's site, sorted by
/// what the app does about it (`docs/protocol.md`, Errors).
enum ConnectError: Error, Hashable, Sendable {
    /// No answer: offline, a timeout, the site down at the network level.
    case offline
    /// The token was revoked or unpaired: forget it, show "Disconnected".
    case revoked
    /// No or unknown token: pair again.
    case unauthorized
    /// The pairing code is not one, was revoked, is too old or was used.
    case pairingCodeInvalid
    case pairingCodeExpired
    case pairingCodeUsed
    /// Too many requests; wait this long, when the server said.
    case rateLimited(retryAfter: TimeInterval?)
    /// The body was over 4 MB: split the batch.
    case payloadTooLarge
    /// One record of a batch is bad (422): split to find it.
    case validationFailed(message: String)
    /// A write raced another: retry once.
    case conflict
    /// A 5xx: retry with backoff.
    case server(status: Int)
    /// Anything else the server refused: do not retry as is.
    case refused(status: Int, code: String, message: String)
    /// The answer could not be read.
    case unreadable
    /// The QR or the address is not one this version can use; `v` other than
    /// 1 means "update the app".
    case unsupportedVersion
    case badAddress

    /// Worth trying again later, with backoff: network errors, 429, 5xx.
    var isRetryable: Bool {
        switch self {
        case .offline, .rateLimited, .server, .conflict: return true
        default: return false
        }
    }

    /// The device is no longer paired, whatever it was doing.
    var disconnects: Bool { self == .revoked }

    /// Builds the error for a response that was not a success.
    static func from(status: Int, body: Data, headers: [String: String]) -> ConnectError {
        let parsed = try? ConnectJSON.decode(ConnectV1.ErrorResponse.self, from: body)
        let code = parsed?.error.code ?? ""
        let message = parsed?.error.message ?? ""
        switch code {
        case .deviceRevoked: return .revoked
        case .unauthorized: return .unauthorized
        case .pairingCodeInvalid: return .pairingCodeInvalid
        case .pairingCodeExpired: return .pairingCodeExpired
        case .pairingCodeUsed: return .pairingCodeUsed
        case .rateLimited: return .rateLimited(retryAfter: retryAfter(headers))
        case .payloadTooLarge: return .payloadTooLarge
        case .validationFailed: return .validationFailed(message: message)
        case .conflict: return .conflict
        default: break
        }
        switch status {
        case 401: return .unauthorized
        case 413: return .payloadTooLarge
        case 429: return .rateLimited(retryAfter: retryAfter(headers))
        case 422: return .validationFailed(message: message)
        case 500...599: return .server(status: status)
        default: return .refused(status: status, code: code.rawValue, message: message)
        }
    }

    private static func retryAfter(_ headers: [String: String]) -> TimeInterval? {
        let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
        return value.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
    }
}

/// The phone's side of the device API: pair, check, sync, upload, files,
/// unpair. Stateless apart from where the site is and the token; the queue,
/// the cursor and the mapping live in `ConnectState`.
struct ConnectClient: Sendable {
    /// The module's base URL, e.g. `https://firm.example/api/zeitkonto`.
    let baseURL: URL
    let transport: ConnectTransport
    /// The device token, `zkd_…`; nil only for pairing.
    var token: String?

    init(baseURL: URL, transport: ConnectTransport, token: String? = nil) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
    }

    // MARK: - Endpoints

    func pair(code: String, device: ConnectV1.DeviceInfo) async throws -> ConnectV1.PairResponse {
        try await call("POST", "v1/device/pair", body: ConnectV1.PairRequest(code: code, device: device), authorized: false)
    }

    func me() async throws -> ConnectV1.MeResponse {
        try await call("GET", "v1/device/me")
    }

    func sync(since cursor: String?) async throws -> ConnectV1.SyncResponse {
        var path = "v1/device/sync"
        if let cursor, !cursor.isEmpty {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            path += "?since=" + (cursor.addingPercentEncoding(withAllowedCharacters: allowed) ?? cursor)
        }
        return try await call("GET", path)
    }

    func upload(_ records: [ConnectV1.UploadRecord]) async throws -> ConnectV1.UploadResponse {
        try await call("POST", "v1/device/upload", body: ConnectV1.UploadRequest(records: records))
    }

    func requestFileUpload(_ request: ConnectV1.FileUploadRequest) async throws -> ConnectV1.FileUploadResponse {
        try await call("POST", "v1/device/files", body: request)
    }

    /// PUTs a file's bytes to the signed URL `requestFileUpload` gave.
    func putFile(_ bytes: Data, contentType: String, to uploadURL: String) async throws {
        guard let url = URL(string: uploadURL) else { throw ConnectError.badAddress }
        let response = try await exchange(ConnectHTTPRequest(
            method: "PUT",
            url: url,
            headers: ["Content-Type": contentType],
            body: bytes
        ))
        guard (200...299).contains(response.status) else {
            throw ConnectError.from(status: response.status, body: response.body, headers: response.headers)
        }
    }

    func unpair() async throws {
        let _: ConnectV1.OkResponse = try await call("POST", "v1/device/unpair", body: [String: String]())
    }

    // MARK: - Plumbing

    /// The full URL of a path under the base, keeping the base's own path
    /// (`/api/zeitkonto`) and any query in `path`.
    func url(for path: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + "/" + path)
    }

    private func call<Response: Decodable>(
        _ method: String,
        _ path: String,
        authorized: Bool = true
    ) async throws -> Response {
        try await call(method, path, bodyData: nil, authorized: authorized)
    }

    private func call<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body,
        authorized: Bool = true
    ) async throws -> Response {
        let data: Data
        do { data = try ConnectJSON.encode(body) } catch { throw ConnectError.unreadable }
        return try await call(method, path, bodyData: data, authorized: authorized)
    }

    private func call<Response: Decodable>(
        _ method: String,
        _ path: String,
        bodyData: Data?,
        authorized: Bool
    ) async throws -> Response {
        guard let url = url(for: path) else { throw ConnectError.badAddress }
        var headers = ["Accept": "application/json", "Zeitkonto-Api": "1"]
        if bodyData != nil { headers["Content-Type"] = "application/json" }
        if authorized {
            guard let token else { throw ConnectError.unauthorized }
            headers["Authorization"] = "Bearer " + token
        }
        let response = try await exchange(ConnectHTTPRequest(method: method, url: url, headers: headers, body: bodyData))
        guard (200...299).contains(response.status) else {
            throw ConnectError.from(status: response.status, body: response.body, headers: response.headers)
        }
        do {
            return try ConnectJSON.decode(Response.self, from: response.body)
        } catch {
            throw ConnectError.unreadable
        }
    }

    private func exchange(_ request: ConnectHTTPRequest) async throws -> ConnectHTTPResponse {
        do {
            return try await transport.send(request)
        } catch let error as ConnectError {
            throw error
        } catch {
            throw ConnectError.offline
        }
    }
}

/// Reading what the QR code holds, or what was typed.
enum ConnectPairing {
    /// The QR's JSON: `{ "v": 1, "url": …, "code": … }`.
    static func parseQR(_ text: String) throws -> (url: URL, code: String) {
        guard let data = text.data(using: .utf8),
              let qr = try? ConnectJSON.decode(ConnectV1.PairingQr.self, from: data) else {
            throw ConnectError.badAddress
        }
        guard qr.v == ConnectV1.apiVersion else { throw ConnectError.unsupportedVersion }
        guard let url = address(qr.url) else { throw ConnectError.badAddress }
        guard let code = normalizedCode(qr.code) else { throw ConnectError.pairingCodeInvalid }
        return (url, code)
    }

    /// A typed address: `https://` added when it was left out; nothing but
    /// https (or http to a machine on the desk, for trying a site out).
    static func address(_ typed: String) -> URL? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.lowercased().hasPrefix("https://") && !text.lowercased().hasPrefix("http://") {
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return nil }
        if scheme == "http" && !(host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")) { return nil }
        return url
    }

    /// The code as the server wants it: spaces and dashes taken out, upper
    /// case; nil when what is left is not eight letters and digits.
    static func normalizedCode(_ typed: String) -> String? {
        let code = typed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == 8, code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return code
    }

    /// The firm's site as a person reads it: the host, without `www.`.
    static func host(of url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
