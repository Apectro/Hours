import Foundation

/// A company's site in a box: answers the device API in memory, by the
/// protocol's rules, so the tests and the UI tests (`-hours-connect-stub`)
/// can pair, sync and send without a network. Nothing it says is real.
final class ConnectStubTransport: ConnectTransport, @unchecked Sendable {
    static let code = "K7QF3MZP"
    static let baseURL = URL(string: "https://firm.example/api/zeitkonto")!
    private static let token = "zkd_stub"

    private let lock = NSLock()
    private var revision = 0
    private var sites: [(rev: Int, site: ConnectV1.Site)] = []
    private var crew: [(rev: Int, member: ConnectV1.CrewMember)] = []
    private var assignments: [(rev: Int, assignment: ConnectV1.Assignment)] = []
    private var tombstones: [(rev: Int, tombstone: ConnectV1.Tombstone)] = []
    private var comments: [(rev: Int, comment: ConnectV1.Comment)] = []
    private var reviews: [(rev: Int, review: ConnectV1.Review)] = []
    private var stored: [String: (version: Int, data: JSONValue?)] = [:]
    private var directorEdited: [String: Int] = [:]
    private var uploadedFiles: Set<String> = []
    private var paired = false
    private var revoked = false
    private var planned: [Result<ConnectHTTPResponse, Error>] = []

    let company = ConnectV1.CompanySummary(id: "8eccf663-ecf2-554d-85cd-63dc76483fe0", name: "Beispiel Bau GmbH", timeZone: "Europe/Vienna", breaksPaid: false, rounding: "exact")
    var member: ConnectV1.CrewMember?
    /// Every request, in order, for the tests to read.
    private(set) var requests: [ConnectHTTPRequest] = []

    init(member: ConnectV1.CrewMember? = nil) {
        self.member = member
    }

    /// The firm the UI tests pair with: one site with its usual day, the
    /// team leader the phone is paired for and two workers on it.
    static func sample() -> ConnectStubTransport {
        let leader = person("0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11", "Marko", role: .teamLeader)
        let stub = ConnectStubTransport(member: leader)
        let site = "a2364fc3-f9d6-51dc-9eb9-41868669e10f"
        stub.addSite(ConnectV1.Site(
            id: site,
            name: "Hauptstraße 12",
            address: "Hauptstraße 12\n1040 Wien",
            workDays: [2, 3, 4, 5, 6],
            usualDay: ConnectV1.UsualDay(start: "07:00", end: "15:30", breakMinutes: 30),
            version: 1,
            origin: "director",
            updatedAt: "2026-09-28T14:02:00Z"
        ))
        stub.addPerson(leader)
        stub.addPerson(person("eabdee49-f0eb-575b-9032-773c56337457", "Ivan"))
        stub.addPerson(person("f8c70eaf-9606-5773-a6b7-c99593ec5ffd", "Luka"))
        stub.assign("5aedadae-1c8a-56f2-9738-cdb7849f3949", leader.id, to: site)
        stub.assign("28e27f54-4818-53f1-9643-412a4d57a2f0", "eabdee49-f0eb-575b-9032-773c56337457", to: site)
        stub.assign("a30a5be7-4762-5eac-b20f-de1d3ff07476", "f8c70eaf-9606-5773-a6b7-c99593ec5ffd", to: site)
        return stub
    }

    static func person(_ id: String, _ name: String, role: ConnectV1.CrewRole = .worker) -> ConnectV1.CrewMember {
        ConnectV1.CrewMember(id: id, name: name, role: role, version: 1, origin: "director", updatedAt: "2026-09-28T14:10:00Z")
    }

    // MARK: - The office's side

    func addSite(_ site: ConnectV1.Site) { locked { revision += 1; sites.removeAll { $0.site.id == site.id }; sites.append((revision, site)) } }
    func addPerson(_ member: ConnectV1.CrewMember) { locked { revision += 1; crew.removeAll { $0.member.id == member.id }; crew.append((revision, member)) } }

    func assign(_ id: String, _ memberID: String, to siteID: String, to end: String? = nil) {
        locked {
            revision += 1
            assignments.removeAll { $0.assignment.id == id }
            assignments.append((revision, ConnectV1.Assignment(id: id, siteId: siteID, memberId: memberID, to: end, version: 1, origin: "director", updatedAt: "2026-09-28T14:12:00Z")))
        }
    }

    func delete(_ kind: ConnectV1.RecordKind, _ id: String) {
        locked {
            revision += 1
            sites.removeAll { $0.site.id == id }
            crew.removeAll { $0.member.id == id }
            assignments.removeAll { $0.assignment.id == id }
            tombstones.append((revision, ConnectV1.Tombstone(kind: kind, id: id, deletedAt: "2026-11-02T10:00:00Z")))
        }
    }

    /// The office returns a record with a comment: its version goes up, and
    /// an upload based on an older one is a conflict.
    func returnRecord(_ kind: ConnectV1.RecordKind, _ id: String, comment: String) {
        locked {
            revision += 1
            let key = ConnectRecordKey.make(kind, id)
            let version = (stored[key]?.version ?? 1) + 1
            stored[key] = (version, stored[key]?.data)
            directorEdited[key] = version
            let note = ConnectV1.Comment(
                id: ConnectID.string(ConnectUUID.v5("stubComment:" + key + ":" + String(version))),
                target: ConnectV1.CommentTarget(kind: kind, id: id),
                body: comment,
                purpose: "return",
                author: ConnectV1.CommentAuthor(kind: "director", name: "Office"),
                createdAt: "2026-11-02T09:30:00Z"
            )
            comments.append((revision, note))
            reviews.append((revision, ConnectV1.Review(kind: kind, id: id, version: version, state: "returned", changedAt: "2026-11-02T09:30:00Z", commentIds: [note.id])))
        }
    }

    /// The device is revoked from the office.
    func revoke() { locked { revoked = true } }

    /// The next answers, instead of the stub's own: a 503, a 429, no network.
    func plan(_ responses: [Result<ConnectHTTPResponse, Error>]) { locked { planned += responses } }

    func storedVersion(_ kind: ConnectV1.RecordKind, _ id: String) -> Int? {
        locked { stored[ConnectRecordKey.make(kind, id)]?.version }
    }

    func storedData(_ kind: ConnectV1.RecordKind, _ id: String) -> JSONValue? {
        locked { stored[ConnectRecordKey.make(kind, id)]?.data ?? nil }
    }

    var isRevoked: Bool { locked { revoked } }

    // MARK: - The device API

    func send(_ request: ConnectHTTPRequest) async throws -> ConnectHTTPResponse {
        try locked {
            requests.append(request)
            if !planned.isEmpty { return try planned.removeFirst().get() }
            return handle(request)
        }
    }

    private func handle(_ request: ConnectHTTPRequest) -> ConnectHTTPResponse {
        if request.url.host == "stub.invalid" {
            uploadedFiles.insert(request.url.lastPathComponent)
            return ConnectHTTPResponse(status: 200, headers: [:], body: Data())
        }
        let path = request.url.path
        if path.hasSuffix("/v1/device/pair") {
            guard let body = request.body, let pair = try? ConnectJSON.decode(ConnectV1.PairRequest.self, from: body),
                  ConnectPairing.normalizedCode(pair.code) == Self.code else {
                return error(400, "pairing_code_invalid")
            }
            guard !paired || revoked else { return error(410, "pairing_code_used") }
            paired = true
            revoked = false
            return json(201, ConnectV1.PairResponse(apiVersion: 1, token: Self.token, device: device(pair.device.name), company: company, member: member, limits: .standard))
        }
        guard request.headers["Authorization"] == "Bearer " + Self.token, paired else { return error(401, "unauthorized") }
        guard !revoked else { return error(401, "device_revoked") }

        if path.hasSuffix("/v1/device/me") {
            return json(200, ConnectV1.MeResponse(apiVersion: 1, device: device("Phone"), company: company, member: member, limits: .standard))
        }
        if path.hasSuffix("/v1/device/sync") {
            let since = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "since" }?.value
                .flatMap { Int($0.replacingOccurrences(of: "c1.", with: "")) }
            let after = since ?? -1
            return json(200, ConnectV1.SyncResponse(
                cursor: "c1." + String(revision),
                hasMore: false,
                full: since == nil,
                serverTime: "2026-11-02T10:00:00Z",
                company: company,
                sites: sites.filter { $0.rev > after }.map(\.site),
                crew: crew.filter { $0.rev > after }.map(\.member),
                assignments: assignments.filter { $0.rev > after }.map(\.assignment),
                comments: comments.filter { $0.rev > after }.map(\.comment),
                reviews: reviews.filter { $0.rev > after }.map(\.review),
                tombstones: since == nil ? [] : tombstones.filter { $0.rev > after }.map(\.tombstone)
            ))
        }
        if path.hasSuffix("/v1/device/files") {
            guard let body = request.body, let file = try? ConnectJSON.decode(ConnectV1.FileUploadRequest.self, from: body) else {
                return error(422, "validation_failed")
            }
            return json(200, ConnectV1.FileUploadResponse(
                fileId: file.fileId,
                path: "company/" + company.id + "/" + file.purpose.rawValue + "/" + file.fileId,
                uploadUrl: "https://stub.invalid/upload/" + file.fileId,
                uploadToken: "stub",
                expiresAt: "2026-11-02T12:00:00Z",
                alreadyUploaded: uploadedFiles.contains(file.fileId)
            ))
        }
        if path.hasSuffix("/v1/device/upload") {
            guard let body = request.body, let upload = try? ConnectJSON.decode(ConnectV1.UploadRequest.self, from: body),
                  (1...200).contains(upload.records.count) else {
                return error(422, "validation_failed")
            }
            return json(200, ConnectV1.UploadResponse(results: upload.records.map(result)))
        }
        if path.hasSuffix("/v1/device/unpair") {
            revoked = true
            return json(200, ConnectV1.OkResponse(ok: true))
        }
        return error(404, "not_found")
    }

    /// The protocol's idempotency rules, enough of them to drive the phone.
    private func result(_ record: ConnectV1.UploadRecord) -> ConnectV1.UploadResult {
        let key = ConnectRecordKey.make(record.kind, record.id)
        let ownedByOffice = sites.contains { ConnectID.same($0.site.id, record.id) }
            || crew.contains { ConnectID.same($0.member.id, record.id) }
            || assignments.contains { ConnectID.same($0.assignment.id, record.id) }
        if record.kind.sendsFirst, ownedByOffice {
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .stale, version: 1, reason: "directorOwned", server: nil)
        }
        if record.data.flatMap({ containsYou($0) }) == true {
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .rejected, version: 0, reason: "unmappedYou",
                                          error: ConnectV1.UploadError(code: "validation_failed", message: "The app's You id was sent."))
        }
        let base = record.baseVersion ?? (record.version - 1)
        guard let existing = stored[key] else {
            stored[key] = (record.version, record.data)
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .accepted, version: record.version)
        }
        if existing.data == record.data, record.version <= existing.version {
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .accepted, version: existing.version, duplicate: true)
        }
        if let edited = directorEdited[key], base < edited {
            let notes = comments.map(\.comment).filter { ConnectID.same($0.target.id, record.id) }
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .conflict, version: existing.version, reason: "returned", server: existing.data, comments: notes)
        }
        if record.version <= existing.version {
            return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .stale, version: existing.version, reason: "newer", server: existing.data)
        }
        stored[key] = (record.version, record.data)
        directorEdited[key] = nil
        return ConnectV1.UploadResult(kind: record.kind, id: record.id, status: .accepted, version: record.version)
    }

    private func containsYou(_ value: JSONValue) -> Bool {
        switch value {
        case let .string(text): return ConnectID.same(text, CrewMember.youID.uuidString)
        case let .array(items): return items.contains(where: containsYou)
        case let .object(object): return object.values.contains(where: containsYou)
        default: return false
        }
    }

    private func device(_ name: String) -> ConnectV1.Device {
        ConnectV1.Device(id: "4cbf616d-adf0-5d1b-a6dd-27a0c244559a", name: name, model: nil, platform: "ios", appVersion: nil,
                         crewMemberId: member?.id, label: nil, pairedAt: "2026-10-01T06:40:00Z", lastSeenAt: nil, revokedAt: nil)
    }

    private func json<T: Encodable>(_ status: Int, _ value: T) -> ConnectHTTPResponse {
        ConnectHTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: (try? ConnectJSON.encode(value)) ?? Data())
    }

    private func error(_ status: Int, _ code: String) -> ConnectHTTPResponse {
        json(status, ConnectV1.ErrorResponse(error: ConnectV1.ErrorBody(code: ConnectV1.ErrorCode(rawValue: code), message: code)))
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
