import Foundation

/// The company this phone is connected to, and as whom. Kept in the app's
/// settings on this device (not the iCloud copy, not the backup file); the
/// token beside it is in the Keychain.
struct ConnectAccount: Codable, Hashable, Sendable {
    /// The module's base URL, e.g. `https://firm.example/api/zeitkonto`.
    var baseURL: String
    var companyID: String
    var companyName: String
    var deviceID: String
    /// The person the office paired the phone for; nil when it chose nobody.
    var memberID: String?
    var memberName: String?
    var pairedAt: Date

    var url: URL? { URL(string: baseURL) }
    var host: String { url.map(ConnectPairing.host(of:)) ?? baseURL }

    private enum CodingKeys: String, CodingKey {
        case baseURL, companyID, companyName, deviceID, memberID, memberName, pairedAt
    }

    init(baseURL: String, companyID: String, companyName: String, deviceID: String, memberID: String?, memberName: String?, pairedAt: Date) {
        self.baseURL = baseURL
        self.companyID = companyID
        self.companyName = companyName
        self.deviceID = deviceID
        self.memberID = memberID
        self.memberName = memberName
        self.pairedAt = pairedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        companyID = container.lenient(.companyID, "")
        companyName = container.lenient(.companyName, "")
        deviceID = container.lenient(.deviceID, "")
        memberID = container.lenientOptional(.memberID)
        memberName = container.lenientOptional(.memberName)
        pairedAt = container.lenient(.pairedAt, Date(timeIntervalSince1970: 0))
    }
}

/// What a send did.
struct ConnectSendReport: Hashable, Sendable {
    var batches = 0
    var accepted = 0
    var serverCopies: [ConnectV1.UploadResult] = []
    var conflicts: [ConnectConflict] = []
    var rejected: [ConnectRejection] = []
    /// Why it stopped before the queue was empty, if it did.
    var stoppedBy: ConnectError?
    /// It did not start: the backoff says not yet.
    var deferred = false
}

/// The steps of a connection, over a `ConnectClient`: pairing, receiving and
/// sending. Each takes the state and gives it back changed; the app keeps
/// it, writes the store, and decides when to run them.
enum ConnectSession {
    // MARK: - Pairing

    /// `POST /v1/device/pair`. The person the office chose is "You"; with
    /// nobody chosen, "You" gets an id of its own, made here, and is sent
    /// as a person like anyone added on the phone.
    static func pair(
        client: ConnectClient,
        code typed: String,
        device: ConnectV1.DeviceInfo,
        now: Date,
        newID: () -> UUID = UUID.init
    ) async throws -> (token: String, account: ConnectAccount, state: ConnectState) {
        guard let code = ConnectPairing.normalizedCode(typed) else { throw ConnectError.pairingCodeInvalid }
        let response = try await client.pair(code: code, device: device)
        guard response.apiVersion == ConnectV1.apiVersion else { throw ConnectError.unsupportedVersion }
        var state = ConnectState()
        state.limits = response.limits
        if let member = response.member, let id = ConnectID.uuid(member.id) {
            state.people.you = id
            state.people.company[id] = ConnectPeople.ConnectPerson(name: member.name, hidden: member.hidden)
        } else if let id = ConnectID.uuid(response.device.crewMemberId) {
            state.people.you = id
        } else {
            state.people.you = newID()
            state.people.youIsLocal = true
        }
        let account = ConnectAccount(
            baseURL: client.baseURL.absoluteString,
            companyID: response.company.id,
            companyName: response.company.name,
            deviceID: response.device.id,
            memberID: response.member?.id ?? response.device.crewMemberId,
            memberName: response.member?.name,
            pairedAt: now
        )
        return (response.token, account, state)
    }

    // MARK: - Receiving

    /// `GET /v1/device/sync`, page after page while `hasMore`, each merged
    /// and written (`apply`) before its cursor is kept. A failure keeps the
    /// cursor of the last page written, so the next sync goes on from there.
    static func receive(
        client: ConnectClient,
        state: ConnectState,
        lock: MonthLock,
        today: CalendarDate,
        now: Date,
        local: () async -> ConnectLocal,
        apply: (ConnectMergePlan) async throws -> Void
    ) async throws -> ConnectState {
        var state = state
        for _ in 0..<50 {
            let page = try await client.sync(since: state.cursor)
            let plan = ConnectMerge.plan(page, state: state, local: await local(), lock: lock, today: today, now: now)
            try await apply(plan)
            state = plan.state
            if !page.hasMore { break }
        }
        return state
    }

    // MARK: - Sending

    /// Sends the queue: for each batch, its files first (`POST
    /// /v1/device/files`, then the bytes, skipped when already there), then
    /// the records (`POST /v1/device/upload`), then the results.
    ///
    /// Network errors, 429 and 5xx stop it with the backoff raised
    /// (Retry-After honoured). A 422 or 413 on a batch halves it until the
    /// bad record is alone, which is dropped and logged; the rest go. A file
    /// the phone no longer has, or the server will not take, drops the
    /// records that need it. A revoked token stops everything.
    static func send(
        client: ConnectClient,
        state: inout ConnectState,
        now: () -> Date,
        jitter: () -> Double,
        fileBytes: (ConnectFileNeed) async -> Data?
    ) async -> ConnectSendReport {
        var report = ConnectSendReport()
        guard state.backoff.allows(at: now()) else {
            report.deferred = true
            return report
        }
        var maxCount = Int.max
        var held = Set<String>()
        for _ in 0..<200 {
            var batch = state.nextBatch(excluding: held, maxCount: maxCount)
            guard !batch.isEmpty else { break }

            // Files first.
            var unusable = Set<String>()
            for file in state.filesToUpload(for: batch) {
                guard let bytes = await fileBytes(file), !bytes.isEmpty else {
                    unusable.insert(file.fileId)
                    continue
                }
                do {
                    let answer = try await client.requestFileUpload(ConnectV1.FileUploadRequest(
                        fileId: file.fileId,
                        purpose: file.purpose,
                        contentType: file.contentType,
                        byteSize: bytes.count,
                        sha256: nil,
                        name: file.name
                    ))
                    if !answer.alreadyUploaded {
                        try await client.putFile(bytes, contentType: file.contentType, to: answer.uploadUrl)
                    }
                    state.uploadedFiles.insert(file.fileId)
                } catch let error as ConnectError {
                    if error.disconnects || error.isRetryable || error == .unauthorized {
                        stop(&report, &state, error, now: now(), jitter: jitter())
                        return report
                    }
                    unusable.insert(file.fileId)
                } catch {
                    stop(&report, &state, .offline, now: now(), jitter: jitter())
                    return report
                }
            }
            if !unusable.isEmpty {
                for entry in batch where entry.files.contains(where: { unusable.contains($0.fileId) }) {
                    state.reject(entry, reason: "fileRefused", message: "", at: now())
                    report.rejected.append(ConnectRejection(kind: entry.kind, id: entry.id, reason: "fileRefused", message: "", at: now()))
                }
                batch.removeAll { entry in entry.files.contains { unusable.contains($0.fileId) } }
                if batch.isEmpty { continue }
            }

            // Then the records.
            do {
                let response = try await client.upload(batch.map(\.uploadRecord))
                let outcome = state.apply(response.results, for: batch, at: now())
                report.batches += 1
                report.accepted += outcome.accepted
                report.serverCopies += outcome.serverCopies
                report.conflicts += outcome.conflicts
                report.rejected += outcome.rejected
                state.backoff.succeeded()
                // Anything the server did not answer for waits for next time.
                let answered = Set(response.results.map { ConnectRecordKey.make($0.kind, $0.id) })
                for entry in batch where !answered.contains(entry.key) { held.insert(entry.key) }
                maxCount = Int.max
            } catch let error as ConnectError {
                switch error {
                case .validationFailed, .payloadTooLarge, .refused(400, _, _):
                    if batch.count > 1 {
                        maxCount = max(1, batch.count / 2)
                    } else if let entry = batch.first {
                        let message: String
                        if case let .validationFailed(text) = error { message = text } else { message = "" }
                        state.reject(entry, reason: "invalid", message: message, at: now())
                        report.rejected.append(ConnectRejection(kind: entry.kind, id: entry.id, reason: "invalid", message: message, at: now()))
                    }
                default:
                    stop(&report, &state, error, now: now(), jitter: jitter())
                    return report
                }
            } catch {
                stop(&report, &state, .offline, now: now(), jitter: jitter())
                return report
            }
        }
        return report
    }

    private static func stop(_ report: inout ConnectSendReport, _ state: inout ConnectState, _ error: ConnectError, now: Date, jitter: Double) {
        report.stoppedBy = error
        if error.isRetryable {
            var retryAfter: TimeInterval?
            if case let .rateLimited(seconds) = error { retryAfter = seconds }
            _ = state.backoff.failed(at: now, retryAfter: retryAfter, jitter: jitter)
        }
    }
}
