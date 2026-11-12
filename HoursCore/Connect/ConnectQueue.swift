import Foundation

/// A record ready to be queued: its kind, id and data as the protocol wants
/// them, and the files it refers to. Built by `ConnectOutbox` from the app's
/// own records.
struct ConnectOutgoing: Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    /// Lower case.
    var id: String
    var data: JSONValue?
    var files: [ConnectFileNeed] = []
    /// The site the record belongs to (all the sites, for a sheet).
    var siteIDs: [UUID] = []
    /// The month it is part of, for a dated record.
    var month: YearMonth?
    var deleted = false

    var key: String { ConnectRecordKey.make(kind, id) }

    init<Record: Encodable>(
        kind: ConnectV1.RecordKind,
        id: String,
        record: Record,
        files: [ConnectFileNeed] = [],
        siteIDs: [UUID],
        month: YearMonth? = nil
    ) throws {
        self.month = month
        self.kind = kind
        self.id = id.lowercased()
        self.data = try ConnectJSON.decode(JSONValue.self, from: ConnectJSON.encode(record))
        self.files = files
        self.siteIDs = siteIDs
    }

    init(deletedKind kind: ConnectV1.RecordKind, id: String, siteIDs: [UUID]) {
        self.kind = kind
        self.id = id.lowercased()
        self.data = nil
        self.siteIDs = siteIDs
        self.deleted = true
    }

    /// What decides "changed": the data without the moment it was built,
    /// which changes every time the outbox runs.
    var contentHash: String {
        guard !deleted, var data else { return "deleted" }
        if case var .object(object) = data {
            object["updatedAt"] = nil
            object["sentAt"] = nil
            data = .object(object)
        }
        let bytes = (try? ConnectJSON.encode(data)) ?? Data()
        return ConnectUUID.digest(bytes)
    }
}

/// What a batch's results asked the app to do, besides dropping what went.
struct ConnectUploadOutcome: Hashable, Sendable {
    /// Server copies to take as the truth (`stale`): a site or person the
    /// director owns, a newer record.
    var serverCopies: [ConnectV1.UploadResult] = []
    /// Records the office changed: shown with the server copy and comments.
    var conflicts: [ConnectConflict] = []
    var rejected: [ConnectRejection] = []
    var accepted = 0
}

extension ConnectState {
    // MARK: - Queueing

    /// Queues each record whose content differs from what it was last
    /// queued as, with its version raised; the same content again is not
    /// queued. A newer change replaces an older entry for the same record,
    /// which keeps its place no more: it goes to the back.
    ///
    /// - Parameter force: queue even unchanged content (a returned sheet
    ///   sent again, "Send to company" tapped again).
    /// - Returns: how many entries were added or replaced.
    @discardableResult
    mutating func enqueue(_ records: [ConnectOutgoing], at now: Date, force: Bool = false) -> Int {
        var changed = 0
        for record in records {
            let key = record.key
            let hash = record.contentHash
            let mark = marks[key]
            if !force, let mark, mark.hash == hash, mark.deleted == record.deleted { continue }
            // A delete of something never sent has nothing to tell.
            if record.deleted, mark == nil { continue }
            let base = mark?.baseVersion ?? 0
            let version = max((mark?.version ?? 0) + 1, base + 1)
            marks[key] = ConnectRecordMark(
                version: version,
                baseVersion: base,
                hash: hash,
                deleted: record.deleted,
                siteIDs: record.siteIDs.isEmpty ? (mark?.siteIDs ?? []) : record.siteIDs,
                month: record.month ?? mark?.month
            )
            queue.removeAll { $0.key == key }
            queue.append(ConnectQueueEntry(
                kind: record.kind,
                id: record.id,
                version: version,
                baseVersion: base,
                deleted: record.deleted,
                data: record.data,
                files: record.files,
                queuedAt: now
            ))
            changed += 1
        }
        return changed
    }

    /// Everything the outbox produced this time, and deletes for records of
    /// the same kinds and sites that were sent before and are gone now.
    /// Only the kinds the outbox covers are compared, and only on the sites
    /// it looked at, so a site left out of a scan never reads as emptied.
    @discardableResult
    mutating func enqueueScan(
        _ records: [ConnectOutgoing],
        kinds: Set<ConnectV1.RecordKind>,
        sites: Set<UUID>,
        at now: Date
    ) -> Int {
        let present = Set(records.map(\.key))
        var deletes: [ConnectOutgoing] = []
        for (key, mark) in marks.sorted(by: { $0.key < $1.key }) where !mark.deleted && !present.contains(key) {
            let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let kind = ConnectV1.RecordKind(rawValue: parts[0])
            guard kinds.contains(kind), !mark.siteIDs.isEmpty, mark.siteIDs.allSatisfy(sites.contains) else { continue }
            deletes.append(ConnectOutgoing(deletedKind: kind, id: parts[1], siteIDs: mark.siteIDs))
        }
        return enqueue(records + deletes, at: now)
    }

    // MARK: - Batches

    /// The next batch: sites, crew and assignments first, then the rest in
    /// the order they were queued; at most `limits.maxBatch` records and
    /// under `limits.maxRequestBytes`. A single record bigger than that
    /// still goes alone, for the server to refuse by name.
    func nextBatch(excluding held: Set<String> = [], maxCount: Int = .max) -> [ConnectQueueEntry] {
        let ordered = queue.enumerated()
            .filter { !held.contains($0.element.key) }
            .sorted { lhs, rhs in
                let left = lhs.element.kind.sendsFirst ? 0 : 1
                let right = rhs.element.kind.sendsFirst ? 0 : 1
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        let maxBatch = max(1, min(limits.maxBatch, 200, maxCount))
        // The envelope around the records: `{"records":[…]}` and commas.
        let budget = max(1, limits.maxRequestBytes) - 64
        var batch: [ConnectQueueEntry] = []
        var bytes = 0
        for entry in ordered {
            guard batch.count < maxBatch else { break }
            let size = ((try? ConnectJSON.encode(entry.uploadRecord))?.count ?? 0) + 1
            if !batch.isEmpty && bytes + size > budget { break }
            batch.append(entry)
            bytes += size
        }
        return batch
    }

    /// The files a batch needs that are not uploaded yet, each once.
    func filesToUpload(for batch: [ConnectQueueEntry]) -> [ConnectFileNeed] {
        var seen = Set<String>()
        return batch.flatMap(\.files).filter { file in
            !uploadedFiles.contains(file.fileId) && seen.insert(file.fileId).inserted
        }
    }

    // MARK: - Results

    /// Applies a batch's results, record by record (`docs/app.md`, The
    /// queue): accepted drops the entry and remembers the server's version;
    /// stale takes the server copy; conflict keeps the local copy and marks
    /// it changed in the office; rejected drops it and logs why. An entry
    /// with no result stays queued. An entry replaced by a newer edit while
    /// the batch was out stays too: only the version that was sent is
    /// dropped.
    @discardableResult
    mutating func apply(_ results: [ConnectV1.UploadResult], for batch: [ConnectQueueEntry], at now: Date) -> ConnectUploadOutcome {
        var outcome = ConnectUploadOutcome()
        let sent = Dictionary(batch.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for result in results {
            let key = ConnectRecordKey.make(result.kind, result.id)
            guard let entry = sent[key] else { continue }
            func drop() { queue.removeAll { $0.key == key && $0.version == entry.version } }
            func remember(base version: Int) {
                guard var mark = marks[key] else { return }
                mark.baseVersion = max(mark.baseVersion, version)
                marks[key] = mark
            }
            switch result.status {
            case .accepted:
                drop()
                remember(base: result.version)
                conflicts[key] = nil
                outcome.accepted += 1
            case .stale:
                drop()
                remember(base: result.version)
                conflicts[key] = nil
                outcome.serverCopies.append(result)
            case .conflict:
                drop()
                remember(base: result.version)
                let conflict = ConnectConflict(
                    kind: result.kind,
                    id: result.id.lowercased(),
                    reason: result.reason ?? "editedOnWeb",
                    serverVersion: result.version,
                    server: result.server,
                    commentIDs: (result.comments ?? []).map(\.id)
                )
                for comment in result.comments ?? [] { comments[comment.id.lowercased()] = comment }
                conflicts[key] = conflict
                outcome.conflicts.append(conflict)
            case .rejected:
                drop()
                let rejection = ConnectRejection(
                    kind: result.kind,
                    id: result.id.lowercased(),
                    reason: result.reason ?? "rejected",
                    message: result.error?.message ?? "",
                    at: now
                )
                rejections = Array((rejections + [rejection]).suffix(50))
                outcome.rejected.append(rejection)
            default:
                // A status this version does not know: tried again later.
                continue
            }
        }
        if outcome.accepted > 0 || !outcome.serverCopies.isEmpty || !outcome.conflicts.isEmpty || !outcome.rejected.isEmpty {
            lastSentAt = now
        }
        return outcome
    }

    /// One record could not be sent at all (a 422 on a batch of one, a
    /// file the server would not take): dropped, logged, never resent as is.
    mutating func reject(_ entry: ConnectQueueEntry, reason: String, message: String, at now: Date) {
        queue.removeAll { $0.key == entry.key && $0.version == entry.version }
        rejections = Array((rejections + [ConnectRejection(kind: entry.kind, id: entry.id, reason: reason, message: message, at: now)]).suffix(50))
    }

    // MARK: - Reading

    /// The state line for a record: what the office last said, else whether
    /// it is waiting or sent.
    func status(of kind: ConnectV1.RecordKind, id: String) -> ConnectRecordStatus {
        let key = ConnectRecordKey.make(kind, id)
        if let conflict = conflicts[key] {
            return conflict.reason == "locked" ? .approved : .returned(comment: commentBodies(conflict.commentIDs).last)
        }
        if let review = reviews[key] {
            switch review.state {
            case "approved": return .approved
            case "returned": return .returned(comment: commentBodies(review.commentIDs).last ?? returnComment(on: kind, id: id))
            default: break
            }
        }
        if queue.contains(where: { $0.key == key }) { return .waiting }
        if marks[key] != nil { return .sent }
        return .notSent
    }

    /// The office's return comment on a record, if there is one.
    func returnComment(on kind: ConnectV1.RecordKind, id: String) -> String? {
        comments.values
            .filter { $0.purpose == "return" && $0.target.kind == kind && ConnectID.same($0.target.id, id) }
            .sorted { $0.createdAt < $1.createdAt }
            .last?.body
    }

    /// The comments on a record or a site, oldest first.
    func comments(on kind: ConnectV1.RecordKind, id: String) -> [ConnectV1.Comment] {
        comments.values
            .filter { $0.target.kind == kind && ConnectID.same($0.target.id, id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// What the office sent back on a site: returned sheets that cover it
    /// and returned or conflicting records on it, newest first.
    func returns(onSite siteID: UUID) -> [ConnectReturn] {
        var found: [String: ConnectReturn] = [:]
        for (key, review) in reviews where review.state == "returned" {
            guard marks[key]?.siteIDs.contains(siteID) == true else { continue }
            found[key] = ConnectReturn(kind: review.kind, id: review.id, comment: commentBodies(review.commentIDs).last ?? returnComment(on: review.kind, id: review.id), at: review.changedAt)
        }
        for (key, conflict) in conflicts where conflict.reason == "returned" {
            guard marks[key]?.siteIDs.contains(siteID) == true else { continue }
            found[key] = ConnectReturn(kind: conflict.kind, id: conflict.id, comment: commentBodies(conflict.commentIDs).last ?? returnComment(on: conflict.kind, id: conflict.id), at: "")
        }
        // Corrected and sent again: no longer a return to act on.
        return found.filter { key, _ in !queue.contains { $0.key == key } }
            .values
            .sorted { $0.at > $1.at }
    }

    private func commentBodies(_ ids: [String]) -> [String] {
        ids.compactMap { comments[$0.lowercased()]?.body }
    }
}

/// A record's state line: "Sent", "Waiting to send", "Approved", "Returned: …".
enum ConnectRecordStatus: Hashable, Sendable {
    case notSent
    case waiting
    case sent
    case approved
    case returned(comment: String?)
}

/// Something the office returned to be corrected.
struct ConnectReturn: Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    var id: String
    var comment: String?
    var at: String
}
