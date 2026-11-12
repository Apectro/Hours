import XCTest
@testable import Hours

/// The upload queue: what is queued, in which order, how often, and what
/// each result does to it.
final class ConnectQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_611_800)
    private let site = UUID(uuidString: "A2364FC3-F9D6-51DC-9EB9-41868669E10F")!

    private func record(_ kind: ConnectV1.RecordKind, _ id: String, note: String = "", files: [ConnectFileNeed] = []) -> ConnectOutgoing {
        try! ConnectOutgoing(kind: kind, id: id, record: ["note": note, "updatedAt": UUID().uuidString], files: files, siteIDs: [site])
    }

    // MARK: - Queueing

    func testTheSameContentIsQueuedOnce() {
        var state = ConnectState()
        XCTAssertEqual(state.enqueue([record(.siteDay, "a")], at: now), 1)
        // Built again a moment later: only the time it was built differs.
        XCTAssertEqual(state.enqueue([record(.siteDay, "a")], at: now), 0, "unchanged content is not queued again")
        XCTAssertEqual(state.queue.count, 1)
        XCTAssertEqual(state.queue[0].version, 1)
    }

    func testANewerEditReplacesTheOlderEntryWithAHigherVersion() {
        var state = ConnectState()
        state.enqueue([record(.siteDay, "a", note: "one"), record(.siteDay, "b")], at: now)
        state.enqueue([record(.siteDay, "a", note: "two")], at: now)
        XCTAssertEqual(state.queue.map(\.id), ["b", "a"], "one entry per record, the newest at the back")
        XCTAssertEqual(state.queue.last?.version, 2)
        XCTAssertEqual(state.queue.last?.data?["note"], .string("two"))
    }

    func testIdsAreKeyedInLowerCase() {
        var state = ConnectState()
        state.enqueue([record(.siteDay, "ABC")], at: now)
        state.enqueue([record(.siteDay, "abc", note: "x")], at: now)
        XCTAssertEqual(state.queue.count, 1)
    }

    func testForceQueuesUnchangedContent() {
        var state = ConnectState()
        state.enqueue([record(.sheet, "s")], at: now)
        XCTAssertEqual(state.enqueue([record(.sheet, "s")], at: now, force: true), 1)
        XCTAssertEqual(state.queue.first?.version, 2)
    }

    func testAVersionIsAlwaysAboveTheServersBase() {
        var state = ConnectState()
        state.enqueue([record(.sheet, "s")], at: now)
        state.marks[ConnectRecordKey.make(.sheet, "s")]?.baseVersion = 5
        state.enqueue([record(.sheet, "s", note: "corrected")], at: now)
        XCTAssertEqual(state.queue.last?.version, 6)
        XCTAssertEqual(state.queue.last?.baseVersion, 5)
    }

    func testAScanQueuesDeletesForWhatIsGone() {
        var state = ConnectState()
        state.enqueueScan([record(.siteDay, "a"), record(.siteDay, "b")], kinds: [.siteDay], sites: [site], at: now)
        state.queue.removeAll()
        state.enqueueScan([record(.siteDay, "a")], kinds: [.siteDay], sites: [site], at: now)
        XCTAssertEqual(state.queue.count, 1)
        XCTAssertEqual(state.queue[0].id, "b")
        XCTAssertTrue(state.queue[0].deleted)
        XCTAssertNil(state.queue[0].uploadRecord.data)
        XCTAssertEqual(state.queue[0].version, 2)
        // Another site's scan does not delete this one's records.
        state.queue.removeAll()
        state.enqueueScan([], kinds: [.siteDay], sites: [UUID()], at: now)
        XCTAssertTrue(state.queue.isEmpty)
    }

    // MARK: - Batches

    func testSitesAndCrewGoFirst() {
        var state = ConnectState()
        state.enqueue([record(.siteDay, "d"), record(.crewMember, "p"), record(.defect, "x"), record(.site, "s"), record(.assignment, "a")], at: now)
        XCTAssertEqual(state.nextBatch().map(\.id), ["p", "s", "a", "d", "x"])
    }

    func testBatchesKeepToTheLimits() {
        var state = ConnectState()
        state.limits = ConnectV1.Limits(maxBatch: 2, maxFileBytes: 1, maxRequestBytes: 4_000_000)
        state.enqueue((0..<5).map { record(.siteDay, "r\($0)") }, at: now)
        XCTAssertEqual(state.nextBatch().count, 2)

        state.limits = ConnectV1.Limits(maxBatch: 200, maxFileBytes: 1, maxRequestBytes: 300)
        let big = String(repeating: "x", count: 150)
        state.queue.removeAll()
        state.marks.removeAll()
        state.enqueue((0..<5).map { record(.siteDay, "r\($0)", note: big) }, at: now)
        XCTAssertEqual(state.nextBatch().count, 1, "under the byte limit")
        XCTAssertEqual(state.nextBatch(maxCount: 1).count, 1)
    }

    func testFilesAreAskedForOnce() {
        var state = ConnectState()
        let file = ConnectFileNeed(fileId: "f1", purpose: .photo, contentType: "image/jpeg", byteSize: 10, source: .diaryPhoto(UUID()))
        state.enqueue([record(.siteDay, "a", files: [file]), record(.defect, "b", files: [file])], at: now)
        XCTAssertEqual(state.filesToUpload(for: state.nextBatch()).map(\.fileId), ["f1"])
        state.uploadedFiles.insert("f1")
        XCTAssertEqual(state.filesToUpload(for: state.nextBatch()), [])
    }

    // MARK: - Results

    func testAcceptedAndStaleAreDone() {
        var state = ConnectState()
        state.enqueue([record(.siteDay, "a"), record(.missingItem, "m")], at: now)
        let batch = state.nextBatch()
        let outcome = state.apply([
            ConnectV1.UploadResult(kind: .siteDay, id: "a", status: .accepted, version: 1),
            ConnectV1.UploadResult(kind: .missingItem, id: "m", status: .stale, version: 3, reason: "newer", server: .object(["state": .string("ordered")])),
        ], for: batch, at: now)
        XCTAssertTrue(state.queue.isEmpty)
        XCTAssertEqual(outcome.accepted, 1)
        XCTAssertEqual(outcome.serverCopies.map(\.id), ["m"])
        XCTAssertEqual(state.marks[ConnectRecordKey.make(.missingItem, "m")]?.baseVersion, 3)
        XCTAssertEqual(state.lastSentAt, now)
        XCTAssertEqual(state.status(of: .siteDay, id: "a"), .sent)
    }

    func testAConflictKeepsTheLocalCopyAndShowsTheComment() {
        var state = ConnectState()
        state.enqueue([record(.sheet, "s")], at: now)
        let comment = ConnectV1.Comment(
            id: "C1",
            target: ConnectV1.CommentTarget(kind: .sheet, id: "s"),
            body: "Ivan on the 28th: the break was at the other site",
            purpose: "return",
            author: ConnectV1.CommentAuthor(kind: "director", name: "Office"),
            createdAt: "2026-11-02T09:30:00Z"
        )
        let outcome = state.apply([
            ConnectV1.UploadResult(kind: .sheet, id: "s", status: .conflict, version: 2, reason: "returned", server: .object([:]), comments: [comment]),
        ], for: state.nextBatch(), at: now)
        XCTAssertEqual(outcome.conflicts.count, 1)
        XCTAssertTrue(state.queue.isEmpty, "nothing is resent unchanged")
        XCTAssertEqual(state.status(of: .sheet, id: "s"), .returned(comment: "Ivan on the 28th: the break was at the other site"))
        XCTAssertEqual(state.returns(onSite: site).map(\.comment), ["Ivan on the 28th: the break was at the other site"])

        // Corrected and sent again: above the server's version, based on it.
        state.enqueue([record(.sheet, "s", note: "corrected")], at: now)
        XCTAssertEqual(state.queue.last?.version, 3)
        XCTAssertEqual(state.queue.last?.baseVersion, 2)
        XCTAssertEqual(state.status(of: .sheet, id: "s"), .returned(comment: "Ivan on the 28th: the break was at the other site"))
        XCTAssertTrue(state.returns(onSite: site).isEmpty, "corrected and waiting: no longer a return to act on")
        state.apply([ConnectV1.UploadResult(kind: .sheet, id: "s", status: .accepted, version: 3)], for: state.nextBatch(), at: now)
        XCTAssertNil(state.conflicts[ConnectRecordKey.make(.sheet, "s")])
    }

    func testRejectedIsDroppedAndLogged() {
        var state = ConnectState()
        state.enqueue([record(.delivery, "d")], at: now)
        state.apply([
            ConnectV1.UploadResult(kind: .delivery, id: "d", status: .rejected, version: 0, reason: "unknownSite",
                                   error: ConnectV1.UploadError(code: "not_found", message: "No such site in this company.")),
        ], for: state.nextBatch(), at: now)
        XCTAssertTrue(state.queue.isEmpty)
        XCTAssertEqual(state.rejections.map(\.reason), ["unknownSite"])
        // The same content again is not resent.
        XCTAssertEqual(state.enqueue([record(.delivery, "d")], at: now), 0)
    }

    func testAnEditWhileTheBatchWasOutStaysQueued() {
        var state = ConnectState()
        state.enqueue([record(.siteDay, "a")], at: now)
        let batch = state.nextBatch()
        state.enqueue([record(.siteDay, "a", note: "edited meanwhile")], at: now)
        state.apply([ConnectV1.UploadResult(kind: .siteDay, id: "a", status: .accepted, version: 1)], for: batch, at: now)
        XCTAssertEqual(state.queue.map(\.version), [2], "only the version that was sent is dropped")
    }

    func testTheFixturesResultsApply() throws {
        let request = try ConnectFixtures.decode(ConnectV1.UploadRequest.self, "device.upload.request")
        let response = try ConnectFixtures.decode(ConnectV1.UploadResponse.self, "device.upload.response")
        var state = ConnectState()
        let outgoing = request.records.map { record -> ConnectOutgoing in
            var out = ConnectOutgoing(deletedKind: record.kind, id: record.id, siteIDs: [site])
            out.deleted = false
            out.data = record.data
            return out
        }
        state.enqueue(outgoing, at: now)
        let outcome = state.apply(response.results, for: state.nextBatch(), at: now)
        XCTAssertTrue(state.queue.isEmpty)
        XCTAssertEqual(outcome.accepted, 6)
        XCTAssertEqual(outcome.serverCopies.count, 1)
        XCTAssertEqual(outcome.conflicts.map(\.reason), ["returned"])
        XCTAssertEqual(outcome.rejected.map(\.reason), ["unknownSite"])
        XCTAssertEqual(state.status(of: .sheet, id: "490ac112-e922-5f2a-98da-81144aa5d13e"),
                       .returned(comment: "Ivan on 28 October: please split the break correctly, 30 min at Schulzentrum."))
    }

    // MARK: - Backoff

    func testBackoffDoublesFromFiveSecondsToFifteenMinutes() {
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 0), 0)
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 1), 5)
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 2), 10)
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 3), 20)
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 9), 900)
        XCTAssertEqual(ConnectBackoff.delay(afterFailures: 40), 900)
    }

    func testBackoffJittersAndHonoursRetryAfter() {
        var backoff = ConnectBackoff()
        XCTAssertEqual(backoff.failed(at: now, jitter: 0.5), 5, accuracy: 0.001)
        XCTAssertFalse(backoff.allows(at: now.addingTimeInterval(4)))
        XCTAssertTrue(backoff.allows(at: now.addingTimeInterval(5)))
        XCTAssertEqual(backoff.failed(at: now, jitter: 0), 8, accuracy: 0.001, "a fifth less at the low end")
        XCTAssertEqual(backoff.failed(at: now, jitter: 1), 24, accuracy: 0.001, "a fifth more at the high end")
        XCTAssertEqual(backoff.failed(at: now, retryAfter: 120, jitter: 0.5), 120, accuracy: 0.001)
        backoff.succeeded()
        XCTAssertTrue(backoff.allows(at: now))
        XCTAssertEqual(backoff.failures, 0)
    }

    // MARK: - Sending through the stub

    private func pairedStub() async throws -> (ConnectStubTransport, ConnectClient, ConnectState) {
        let stub = ConnectStubTransport.sample()
        let pairing = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub)
        let paired = try await ConnectSession.pair(client: pairing, code: ConnectStubTransport.code, device: ConnectV1.DeviceInfo(name: "t", appVersion: "1"), now: now)
        return (stub, ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token), paired.state)
    }

    func testSendUploadsFilesThenRecords() async throws {
        var (stub, client, state) = try await pairedStub()
        let file = ConnectFileNeed(fileId: "6949219a-d46e-5306-ba54-9e3cc349ec18", purpose: .sheetPdf, contentType: "application/pdf", byteSize: 3, source: .stored("x.pdf"))
        state.enqueue([record(.sheet, "490ac112-e922-5f2a-98da-81144aa5d13e", files: [file]), record(.siteDay, "a")], at: now)
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in Data("pdf".utf8) })
        XCTAssertNil(report.stoppedBy)
        XCTAssertEqual(report.accepted, 2)
        XCTAssertTrue(state.queue.isEmpty)
        let paths = stub.requests.map { $0.method + " " + $0.url.path }
        XCTAssertEqual(paths.suffix(3), ["POST /api/zeitkonto/v1/device/files", "PUT /upload/6949219a-d46e-5306-ba54-9e3cc349ec18", "POST /api/zeitkonto/v1/device/upload"])
        XCTAssertTrue(state.uploadedFiles.contains(file.fileId))

        // Sent again (a corrected sheet): the file is not uploaded twice.
        state.enqueue([record(.sheet, "490ac112-e922-5f2a-98da-81144aa5d13e", note: "v2", files: [file])], at: now)
        let before = stub.requests.count
        _ = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in Data("pdf".utf8) })
        XCTAssertEqual(stub.requests.count - before, 1, "only the upload")
    }

    func testOfflineKeepsTheQueueAndBacksOff() async throws {
        var (stub, client, state) = try await pairedStub()
        state.enqueue([record(.siteDay, "a")], at: now)
        stub.plan([.failure(URLError(.notConnectedToInternet))])
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.stoppedBy, .offline)
        XCTAssertEqual(state.queue.count, 1, "nothing is lost offline")
        XCTAssertEqual(state.backoff.failures, 1)
        // Too soon: it does not even try.
        let soon = await ConnectSession.send(client: client, state: &state, now: { self.now.addingTimeInterval(2) }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertTrue(soon.deferred)
        // Later, it goes.
        let later = await ConnectSession.send(client: client, state: &state, now: { self.now.addingTimeInterval(6) }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(later.accepted, 1)
        XCTAssertEqual(state.backoff.failures, 0)
    }

    func testRateLimitedWaitsAsLongAsTheServerSays() async throws {
        var (stub, client, state) = try await pairedStub()
        state.enqueue([record(.siteDay, "a")], at: now)
        let body = try ConnectJSON.encode(ConnectV1.ErrorResponse(error: ConnectV1.ErrorBody(code: .rateLimited, message: "slow down")))
        stub.plan([.success(ConnectHTTPResponse(status: 429, headers: ["Retry-After": "60"], body: body))])
        _ = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(state.backoff.notBefore, now.addingTimeInterval(60))
    }

    func testABadRecordIsFoundBySplittingTheBatch() async throws {
        var (stub, client, state) = try await pairedStub()
        state.enqueue([record(.siteDay, "a"), record(.siteDay, "bad"), record(.siteDay, "c")], at: now)
        let invalid = try ConnectJSON.encode(ConnectV1.ErrorResponse(error: ConnectV1.ErrorBody(code: .validationFailed, message: "records.1.data.date: Not a calendar date")))
        let answer = ConnectHTTPResponse(status: 422, headers: [:], body: invalid)
        // The whole batch, then its first half [a]: fine, then [bad] alone.
        stub.plan([.success(answer)])
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.accepted, 3, "with only the first answer planned, the halves go through")
        XCTAssertTrue(state.queue.isEmpty)

        state.enqueue([record(.siteDay, "x"), record(.siteDay, "y", note: "bad")], at: now)
        stub.plan([.success(answer), .success(answer)])
        let second = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(second.rejected.map(\.id), ["x"], "alone and still refused: dropped and logged")
        XCTAssertEqual(second.accepted, 1)
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testRevokedStopsSending() async throws {
        var (stub, client, state) = try await pairedStub()
        state.enqueue([record(.siteDay, "a")], at: now)
        stub.revoke()
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.stoppedBy, .revoked)
        XCTAssertEqual(state.backoff.failures, 0, "not a reason to retry")
    }

    func testAMissingFileDropsTheRecordsThatNeedIt() async throws {
        var (_, client, state) = try await pairedStub()
        let file = ConnectFileNeed(fileId: "gone", purpose: .photo, contentType: "image/jpeg", byteSize: 3, source: .diaryPhoto(UUID()))
        state.enqueue([record(.siteDay, "a", files: [file]), record(.siteDay, "b")], at: now)
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.rejected.map(\.id), ["a"])
        XCTAssertEqual(report.accepted, 1)
    }

    func testADuplicateSendIsHarmless() async throws {
        var (stub, client, state) = try await pairedStub()
        state.enqueue([record(.siteDay, "a")], at: now)
        let entry = state.queue[0]
        _ = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        // The answer was lost: the same entry is sent again.
        state.queue = [entry]
        let again = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(again.accepted, 1)
        XCTAssertEqual(stub.storedVersion(.siteDay, "a"), 1)
    }
}
