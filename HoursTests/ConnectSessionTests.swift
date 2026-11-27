import XCTest
@testable import Hours

/// The whole round trip against the stub company, as the app runs it: pair,
/// receive, write a day, queue it, send it, have it returned, correct it.
final class ConnectSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_611_800)
    private let today = CalendarDate(year: 2026, month: 11, day: 2)
    private let siteID = UUID(uuidString: "a2364fc3-f9d6-51dc-9eb9-41868669e10f")!

    /// The phone's store, as plain values.
    private final class Phone {
        var sites: [Site] = []
        var crew: [CrewMember] = []
        var setups: [UUID: SiteSetup] = [:]
        var days: [SiteDay] = []

        var local: ConnectLocal { ConnectLocal(sites: sites, crew: crew, setups: setups) }

        func apply(_ plan: ConnectMergePlan) {
            for site in plan.sites {
                sites.removeAll { $0.id == site.id }
                sites.append(site)
            }
            for member in plan.crew {
                crew.removeAll { $0.id == member.id }
                crew.append(member)
            }
            setups.merge(plan.setups) { _, new in new }
        }
    }

    private func scan(_ phone: Phone, _ state: inout ConnectState) {
        let input = ConnectOutboxInput(sites: phone.sites, crew: phone.crew, setups: phone.setups, siteDays: phone.days, yourName: "Marko", now: now)
        state.people = state.people.linking(phone.crew)
        state.enqueueScan(ConnectOutbox.records(input, state: state), kinds: ConnectOutbox.scannedKinds, sites: ConnectOutbox.scope(state, sites: phone.sites), at: now)
    }

    func testPairReceiveWriteSendReturnCorrect() async throws {
        let stub = ConnectStubTransport.sample()
        let phone = Phone()
        let paired = try await ConnectSession.pair(
            client: ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub),
            code: "K7QF-3MZP",
            device: ConnectV1.DeviceInfo(name: "Phone", appVersion: "1.3"),
            now: now
        )
        let client = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token)

        // The first full sync: the company's site, its usual day, its crew.
        var state = try await ConnectSession.receive(client: client, state: paired.state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        XCTAssertEqual(phone.sites.map(\.name), ["Hauptstraße 12"])
        XCTAssertEqual(phone.setups[siteID]?.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(phone.crew.map(\.name).sorted(), ["Ivan", "Luka"])
        XCTAssertNotNil(state.cursor)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0, "nothing of the office's is sent back")

        // A day: Same as usual for the whole crew.
        let setup = try XCTUnwrap(phone.setups[siteID])
        phone.days = [SiteDay(
            siteID: siteID, date: today, start: setup.start, end: setup.end, breakMinutes: setup.breakMinutes,
            present: [Attendance(memberID: CrewMember.youID)] + phone.crew.map { Attendance(memberID: $0.id) }
        )]
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 1, "1 waiting")
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 1, "looking again changes nothing")

        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.accepted, 1)
        XCTAssertEqual(state.waitingCount, 0, "up to date")
        let dayID = ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: today))
        let sent = try XCTUnwrap(stub.storedData(.siteDay, dayID))
        let people = sent["attendance"].flatMap { value -> [String]? in
            guard case let .array(items) = value else { return nil }
            return items.compactMap { $0["memberId"]?.stringValue }
        }
        XCTAssertEqual(Set(people ?? []), ["0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11", "eabdee49-f0eb-575b-9032-773c56337457", "f8c70eaf-9606-5773-a6b7-c99593ec5ffd"],
                       "You and the crew as the company's people")
        XCTAssertEqual(state.status(of: .siteDay, id: dayID), .sent)

        // The office returns it; the next sync says so.
        stub.returnRecord(.siteDay, dayID, comment: "Ivan left at noon")
        state = try await ConnectSession.receive(client: client, state: state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        XCTAssertEqual(state.status(of: .siteDay, id: dayID), .returned(comment: "Ivan left at noon"))
        XCTAssertEqual(state.returns(onSite: siteID).map(\.comment), ["Ivan left at noon"])

        // Corrected: a newer version, based on the office's, accepted.
        let ivan = try XCTUnwrap(phone.crew.first { $0.name == "Ivan" })
        phone.days[0].present = phone.days[0].present.map { $0.memberID == ivan.id ? Attendance(memberID: ivan.id, end: TimeOfDay(hour: 12, minute: 0)) : $0 }
        scan(phone, &state)
        XCTAssertEqual(state.queue.first?.baseVersion, 2)
        XCTAssertEqual(state.queue.first?.version, 3)
        let corrected = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(corrected.accepted, 1)
        XCTAssertEqual(stub.storedVersion(.siteDay, dayID), 3)

        // Disconnected by the office: the next call says so.
        stub.revoke()
        do {
            _ = try await ConnectSession.receive(client: client, state: state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
            XCTFail("a revoked device must not sync")
        } catch {
            XCTAssertEqual(error as? ConnectError, .revoked)
        }
    }

    /// The user's own site, shared with the company, comes back from the web
    /// as one of the company's at the next sync, and so do its people and
    /// who is on it. The phone stops sending them then; that must not read
    /// as the site, the people or the assignments being gone. (It did: the
    /// phone sent deletes, the web removed the site, and the next sync
    /// archived it on the phone, while the people were added and deleted
    /// again at every sync.)
    func testAPhoneMadeSiteSurvivesComingBackFromTheWeb() async throws {
        let stub = ConnectStubTransport.sample()
        let phone = Phone()
        let paired = try await ConnectSession.pair(client: ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub), code: ConnectStubTransport.code, device: ConnectV1.DeviceInfo(name: "Phone", appVersion: "1.3"), now: now)
        let client = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token)
        func receive(_ state: ConnectState) async throws -> ConnectState {
            try await ConnectSession.receive(client: client, state: state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        }
        func send(_ state: inout ConnectState) async -> ConnectSendReport {
            await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        }
        var state = try await receive(paired.state)

        let own = Site(name: "Končar", sortOrder: 1)
        phone.sites.append(own)
        phone.crew += [CrewMember(siteID: own.id, name: "Duško"), CrewMember(siteID: own.id, name: "Danilo", sortOrder: 1)]
        state.sharedSites.insert(own.id)
        scan(phone, &state)
        let first = await send(&state)
        XCTAssertTrue(first.rejected.isEmpty)
        let siteKey = ConnectID.string(own.id)
        XCTAssertTrue(stub.holds(.site, siteKey), "the site is the company's now")

        // Back from the web, three rounds: nothing is deleted, nothing flaps.
        for round in 1...3 {
            state = try await receive(state)
            XCTAssertTrue(state.companySites.contains(own.id))
            scan(phone, &state)
            XCTAssertFalse(state.queue.contains(where: \.deleted), "round \(round): no delete is queued")
            _ = await send(&state)
            XCTAssertEqual(state.waitingCount, 0, "round \(round): nothing left to send")
        }
        XCTAssertTrue(stub.holds(.site, siteKey), "still on the web")
        let people = phone.crew.filter { $0.siteID == own.id }
        XCTAssertEqual(people.count, 2)
        for row in people {
            let person = try XCTUnwrap(state.people.rows[row.id])
            XCTAssertTrue(stub.holds(.crewMember, ConnectID.string(person)), "\(row.name) is still the company's")
            XCTAssertTrue(stub.holds(.assignment, ConnectID.string(ConnectUUID.assignmentID(siteID: own.id, personID: person))), "\(row.name) is still on the site")
            XCTAssertFalse(row.isHidden)
        }
        XCTAssertEqual(phone.sites.first { $0.id == own.id }?.isArchived, false, "not archived on the phone")
    }

    /// An upload that still holds the app's own "You" is refused by the
    /// server: the outbox never sends one.
    func testTheStubRefusesTheFixedYou() async throws {
        let stub = ConnectStubTransport.sample()
        let paired = try await ConnectSession.pair(client: ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub), code: ConnectStubTransport.code, device: ConnectV1.DeviceInfo(name: "P", appVersion: "1"), now: now)
        var state = paired.state
        state.enqueue([try ConnectOutgoing(kind: .siteDay, id: "d", record: ["writtenBy": CrewMember.youID.uuidString], siteIDs: [siteID])], at: now)
        let client = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token)
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.rejected.map(\.reason), ["unmappedYou"])
    }

    /// The settings that iCloud and the backup file carry never hold the
    /// connection: the token, the company and the queue live elsewhere.
    func testSettingsAndBackupsDoNotCarryTheConnection() throws {
        let json = String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("connect"))
        XCTAssertFalse(json.contains("token"))
    }
}
