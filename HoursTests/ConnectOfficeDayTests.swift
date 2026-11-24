import XCTest
@testable import Hours

/// Office days (`docs/app.md` of the Connect module, Office days): the days
/// the director wrote or changed on the web, taken into the phone; what a
/// closed month, an unsent local edit and a deleted office day do.
final class ConnectOfficeDayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_611_800)
    private let today = CalendarDate(year: 2026, month: 11, day: 2)
    private let october = YearMonth(year: 2026, month: 10)
    private let hauptstrasse = UUID(uuidString: "a2364fc3-f9d6-51dc-9eb9-41868669e10f")!
    private let schule = UUID(uuidString: "d65be387-0478-5071-8e5c-052d65e0fb8b")!
    private let marko = UUID(uuidString: "0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11")!
    private let ivan = UUID(uuidString: "eabdee49-f0eb-575b-9032-773c56337457")!
    private let luka = UUID(uuidString: "f8c70eaf-9606-5773-a6b7-c99593ec5ffd")!
    private let ante = UUID(uuidString: "f50c64bf-b5e8-53af-9c7b-e2a5960c76c5")!
    private let the29th = CalendarDate(year: 2026, month: 10, day: 29)
    private let the17th = CalendarDate(year: 2026, month: 10, day: 17)

    /// The phone's store, as plain values.
    private final class Phone {
        var sites: [Site] = []
        var crew: [CrewMember] = []
        var setups: [UUID: SiteSetup] = [:]
        var days: [SiteDay] = []

        var local: ConnectLocal { ConnectLocal(sites: sites, crew: crew, setups: setups, siteDays: days) }

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
            for day in plan.siteDays { write(day) }
            for ref in plan.removedSiteDays { delete(ref.siteID, ref.date) }
        }

        func write(_ day: SiteDay) {
            days.removeAll { $0.siteID == day.siteID && $0.date == day.date }
            days.append(day)
        }

        func delete(_ siteID: UUID, _ date: CalendarDate) {
            days.removeAll { $0.siteID == siteID && $0.date == date }
        }

        func day(_ siteID: UUID, _ date: CalendarDate) -> SiteDay? {
            days.first { $0.siteID == siteID && $0.date == date }
        }

        func row(_ name: String, on siteID: UUID) -> CrewMember? {
            crew.first { $0.siteID == siteID && $0.name == name }
        }
    }

    private func fixture() throws -> ConnectV1.SyncResponse {
        try ConnectFixtures.decode(ConnectV1.SyncResponse.self, "device.sync.response")
    }

    private func officeDays() throws -> [ConnectV1.SiteDay] {
        try ConnectFixtures.decode([ConnectV1.SiteDay].self, "october.office-days")
    }

    private func page(_ cursor: String, days: [ConnectV1.SiteDay] = [], tombstones: [String] = []) throws -> ConnectV1.SyncResponse {
        var page = ConnectV1.SyncResponse(cursor: cursor, hasMore: false, full: false, serverTime: "", company: try fixture().company)
        page.siteDays = days
        page.tombstones = tombstones.map { ConnectV1.Tombstone(kind: .siteDay, id: $0, deletedAt: "2026-11-02T10:00:00Z") }
        return page
    }

    /// A phone paired as Marko that has taken the fixture's sites and crews,
    /// but none of its office days.
    private func paired() throws -> (Phone, ConnectState) {
        var state = ConnectState()
        state.people.you = marko
        var first = try fixture()
        first.siteDays = []
        let phone = Phone()
        let plan = ConnectMerge.plan(first, state: state, local: phone.local, lock: .unlocked, today: today, now: now)
        phone.apply(plan)
        return (phone, plan.state)
    }

    private func merge(_ page: ConnectV1.SyncResponse, _ phone: Phone, _ state: inout ConnectState, lock: MonthLock = .unlocked) -> ConnectMergePlan {
        let plan = ConnectMerge.plan(page, state: state, local: phone.local, lock: lock, today: today, now: now)
        phone.apply(plan)
        state = plan.state
        return plan
    }

    private func scan(_ phone: Phone, _ state: inout ConnectState) {
        let input = ConnectOutboxInput(sites: phone.sites, crew: phone.crew, setups: phone.setups, siteDays: phone.days, yourName: "Marko", now: now)
        state.people = state.people.linking(phone.crew)
        state.enqueueScan(ConnectOutbox.records(input, state: state), kinds: ConnectOutbox.scannedKinds, sites: ConnectOutbox.scope(state, sites: phone.sites), at: now)
    }

    private func key(_ siteID: UUID, _ date: CalendarDate) -> String {
        ConnectRecordKey.make(.siteDay, ConnectSiteDayRef(siteID: siteID, date: date).id)
    }

    /// The phone's own day on Hauptstraße on the 29th, sent and accepted as
    /// version 1.
    private func withASentDay(_ phone: Phone, _ state: inout ConnectState) throws -> SiteDay {
        let rows = phone.crew.filter { $0.siteID == hauptstrasse && !$0.isHidden }
        let day = SiteDay(
            siteID: hauptstrasse, date: the29th,
            start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 30), breakMinutes: 30,
            present: [Attendance(memberID: CrewMember.youID)] + rows.map { Attendance(memberID: $0.id) },
            kilometres: 42
        )
        phone.write(day)
        scan(phone, &state)
        let batch = state.nextBatch()
        XCTAssertEqual(batch.map(\.kind), [.siteDay])
        state.apply(batch.map { ConnectV1.UploadResult(kind: $0.kind, id: $0.id, status: .accepted, version: $0.version) }, for: batch, at: now)
        XCTAssertEqual(state.waitingCount, 0)
        return day
    }

    // MARK: - Taking a day

    func testAnOfficeEditReplacesTheLocalDay() throws {
        let (phone, start) = try paired()
        var state = start
        let mine = try withASentDay(phone, &state)

        let plan = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        XCTAssertEqual(plan.siteDays.count, 1)
        let day = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        let lukaRow = try XCTUnwrap(phone.row("Luka Babić", on: hauptstrasse))
        let ivanRow = try XCTUnwrap(phone.row("Ivan Horvat", on: hauptstrasse))
        XCTAssertEqual(Set(day.present.map(\.memberID)), [CrewMember.youID, lukaRow.id, ivanRow.id], "You and the site's own rows, never the company's ids")
        XCTAssertEqual(day.attendance(for: lukaRow.id)?.end, TimeOfDay(hour: 12, minute: 0), "Luka to the doctor at 12:00")
        XCTAssertNil(day.attendance(for: ivanRow.id)?.end)
        XCTAssertEqual(day.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(day.end, TimeOfDay(hour: 15, minute: 30))
        XCTAssertEqual(day.breakMinutes, 30)
        XCTAssertEqual(day.kilometres, 42)
        XCTAssertEqual(day.note, "Luka to the doctor at 12:00 (corrected by the office).")
        XCTAssertEqual(Set(day.allowanceMemberIDs), [CrewMember.youID, lukaRow.id, ivanRow.id])
        XCTAssertEqual(day.jobID, mine.jobID)

        // Its version is the base of whatever the phone sends next.
        let mark = try XCTUnwrap(state.marks[key(hauptstrasse, the29th)])
        XCTAssertEqual(mark.baseVersion, 2)
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: the29th)?.mark, .changed, "a phone's day the office edited")
        XCTAssertEqual(state.officeMarks(siteID: hauptstrasse), [the29th: .changed])
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertNil(state.conflicts[key(hauptstrasse, the29th)])

        // The office's own copy is not sent back to it.
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)
        XCTAssertEqual(state.status(of: .siteDay, id: ConnectSiteDayRef(siteID: hauptstrasse, date: the29th).id), .sent)

        // A later local edit goes out above the office's version, on it.
        var edited = day
        edited.note = "Luka back at 14:00"
        phone.write(edited)
        scan(phone, &state)
        let entry = try XCTUnwrap(state.queue.first)
        XCTAssertEqual(entry.baseVersion, 2)
        XCTAssertEqual(entry.version, 3)
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: the29th), "the phone's again: no longer changed by the office")
    }

    func testADayTheOfficeWroteIsWrittenByTheOffice() throws {
        let (phone, start) = try paired()
        var state = start
        let written = try officeDays().filter(\.isOfficeWritten)
        XCTAssertEqual(written.count, 2)
        let plan = merge(try page("c1.1043", days: written), phone, &state)
        XCTAssertEqual(plan.siteDays.map(\.date), [the17th, CalendarDate(year: 2026, month: 10, day: 24)])
        let day = try XCTUnwrap(phone.day(schule, the17th))
        let anteRow = try XCTUnwrap(phone.row("Ante Novak", on: schule))
        XCTAssertEqual(day.present, [Attendance(memberID: anteRow.id)])
        XCTAssertEqual(day.end, TimeOfDay(hour: 12, minute: 0))
        XCTAssertEqual(state.officeDay(siteID: schule, date: the17th)?.mark, .written)
        XCTAssertEqual(state.marks[key(schule, the17th)]?.baseVersion, 1)
        XCTAssertEqual(state.marks[key(schule, the17th)]?.month, october)
        XCTAssertFalse(plan.crew.contains { $0.id == anteRow.id }, "he is on the site already: his row is not written again")

        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0, "nothing of the office's is sent back")

        // The phone edits the office's day: it stays written by the office.
        var edited = day
        edited.end = TimeOfDay(hour: 13, minute: 0)
        phone.write(edited)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.baseVersion), [1])
        XCTAssertEqual(state.queue.map(\.version), [2])
        XCTAssertEqual(state.officeDay(siteID: schule, date: the17th)?.mark, .written)
    }

    func testSomeoneNotOnTheSitesCrewIsAddedFromTheCompanys() throws {
        let (phone, start) = try paired()
        var state = start
        XCTAssertNil(phone.row("Ante Novak", on: hauptstrasse), "Ante is on the school only")
        var day = try XCTUnwrap(try officeDays().first)
        day.siteId = ConnectID.string(hauptstrasse)
        day.id = ConnectSiteDayRef(siteID: hauptstrasse, date: the17th).id
        // And someone the phone has never heard of.
        day.attendance.append(ConnectV1.Attendance(memberId: "11111111-2222-4333-8444-555555555555"))
        let plan = merge(try page("c1.1043", days: [day]), phone, &state)

        let row = try XCTUnwrap(phone.row("Ante Novak", on: hauptstrasse))
        XCTAssertEqual(plan.crew.map(\.id), [row.id])
        XCTAssertEqual(row.id, ConnectUUID.crewRowID(siteID: hauptstrasse, personID: ante), "the same row on every phone")
        XCTAssertEqual(state.people.rows[row.id], ante, "linked by the company's id")
        XCTAssertTrue(row.isHidden, "named on a day, not put on the site's usual crew")
        XCTAssertEqual(phone.day(hauptstrasse, the17th)?.present.map(\.memberID), [row.id], "the unknown person is left out")

        // He is sent back as himself, not as someone new.
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)
    }

    func testAVersionAlreadyTakenChangesNothing() throws {
        let (phone, start) = try paired()
        var state = start
        _ = merge(try page("c1.1043", days: try officeDays()), phone, &state)
        scan(phone, &state)
        var edited = try XCTUnwrap(phone.day(schule, the17th))
        edited.note = "mine"
        phone.write(edited)
        scan(phone, &state)
        let batch = state.nextBatch()
        state.apply(batch.map { ConnectV1.UploadResult(kind: $0.kind, id: $0.id, status: .accepted, version: $0.version) }, for: batch, at: now)

        // A full sync brings the office's days again, and the phone's own
        // newer version of one of them.
        var again = try officeDays()
        again[0].version = 2
        again[0].editedBy = "device"
        again[0].note = "mine"
        let plan = merge(try page("c1.1050", days: again), phone, &state)
        XCTAssertTrue(plan.siteDays.isEmpty)
        XCTAssertFalse(plan.changesStore)
        XCTAssertEqual(phone.day(schule, the17th)?.note, "mine")
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)

        // A newer office edit is taken.
        again[0].version = 3
        again[0].editedBy = "director"
        again[0].note = "the office again"
        _ = merge(try page("c1.1051", days: again), phone, &state)
        XCTAssertEqual(phone.day(schule, the17th)?.note, "the office again")
        XCTAssertEqual(state.marks[key(schule, the17th)]?.baseVersion, 3)
    }

    func testADayThatIsNotItsSitesAndDatesIsIgnored() throws {
        let (phone, start) = try paired()
        var state = start
        var wrongID = try XCTUnwrap(try officeDays().first)
        wrongID.id = "11111111-2222-4333-8444-555555555555"
        var noVersion = try XCTUnwrap(try officeDays().last)
        noVersion.version = nil
        let plan = merge(try page("c1.1043", days: [wrongID, noVersion]), phone, &state)
        XCTAssertFalse(plan.changesStore)
        XCTAssertTrue(state.officeDays.isEmpty)
        XCTAssertTrue(state.heldOfficeDays.isEmpty)
    }

    // MARK: - A closed month

    func testAClosedMonthIsLeftAloneListedOnceAndTakenWhenReopened() throws {
        let (phone, start) = try paired()
        var state = start
        let mine = try withASentDay(phone, &state)
        let closed = MonthLock(months: [october])

        let plan = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state, lock: closed)
        XCTAssertTrue(plan.siteDays.isEmpty)
        XCTAssertEqual(phone.day(hauptstrasse, the29th), mine, "a closed month is never changed")
        XCTAssertEqual(plan.conflicts, [ConnectMergeConflict(kind: .officeDayInClosedMonth, recordKind: .siteDay, id: ConnectSiteDayRef(siteID: hauptstrasse, date: the29th).id, month: "2026-10")])
        XCTAssertEqual(state.lockedConflicts.count, 1)
        XCTAssertEqual(state.marks[key(hauptstrasse, the29th)]?.baseVersion, 1, "not taken, so not the base")
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: the29th))
        XCTAssertFalse(state.hasOfficeDaysToTake(lock: closed))

        // Still closed at the next sync: not listed again.
        let later = merge(try page("c1.1044"), phone, &state, lock: closed)
        XCTAssertTrue(later.conflicts.isEmpty)
        XCTAssertEqual(state.lockedConflicts.count, 1)

        // Reopened: taken without waiting for the office to send it again.
        XCTAssertTrue(state.hasOfficeDaysToTake(lock: .unlocked))
        let pending = ConnectMerge.planPending(state: state, local: phone.local, lock: .unlocked)
        phone.apply(pending)
        state = pending.state
        XCTAssertEqual(phone.day(hauptstrasse, the29th)?.note, "Luka to the doctor at 12:00 (corrected by the office).")
        XCTAssertEqual(state.marks[key(hauptstrasse, the29th)]?.baseVersion, 2)
        XCTAssertTrue(state.heldOfficeDays.isEmpty)
        XCTAssertFalse(state.hasOfficeDaysToTake(lock: .unlocked))
    }

    // MARK: - An unsent local edit

    func testAnUnsentLocalEditIsSetAsideAndTheOfficesShown() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        var mine = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        mine.note = "my own note"
        phone.write(mine)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 1)
        let id = ConnectSiteDayRef(siteID: hauptstrasse, date: the29th).id

        _ = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        XCTAssertEqual(phone.day(hauptstrasse, the29th)?.note, "Luka to the doctor at 12:00 (corrected by the office).", "the office's copy is applied")
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: the29th)?.mine, ConnectMine(day: mine), "the phone's edit is kept")
        XCTAssertEqual(state.status(of: .siteDay, id: id), .changedByOffice)
        XCTAssertEqual(state.conflicts[key(hauptstrasse, the29th)]?.serverVersion, 2)
        XCTAssertEqual(state.waitingCount, 0, "the old edit is not sent over the office's")
        XCTAssertEqual(state.officeMarks(siteID: hauptstrasse), [the29th: .changed])
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)
        XCTAssertEqual(state.status(of: .siteDay, id: id), .changedByOffice, "until the user chooses")

        // It survives the state file.
        let reread = try JSONDecoder().decode(ConnectState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(reread.officeDay(siteID: hauptstrasse, date: the29th)?.mine?.day, mine)
        XCTAssertEqual(reread, state)

        // "Use the office's".
        var theirs = state
        theirs.useOfficeDay(siteID: hauptstrasse, date: the29th)
        XCTAssertNil(theirs.officeDay(siteID: hauptstrasse, date: the29th)?.mine)
        XCTAssertEqual(theirs.status(of: .siteDay, id: id), .sent)
        XCTAssertEqual(theirs.officeDay(siteID: hauptstrasse, date: the29th)?.mark, .changed)
        scan(phone, &theirs)
        XCTAssertEqual(theirs.waitingCount, 0)

        // "Keep mine": written again, queued on top of the office's version.
        let kept = try XCTUnwrap(state.keepMine(siteID: hauptstrasse, date: the29th))
        XCTAssertEqual(kept.day, mine)
        phone.write(mine)
        scan(phone, &state)
        let entry = try XCTUnwrap(state.queue.first)
        XCTAssertEqual(entry.baseVersion, 2, "the office's version")
        XCTAssertEqual(entry.version, 3)
        XCTAssertEqual(entry.data?["note"]?.stringValue, "my own note")
        XCTAssertEqual(state.status(of: .siteDay, id: id), .waiting)
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: the29th))
        XCTAssertNil(state.keepMine(siteID: hauptstrasse, date: the29th), "chosen once")
    }

    func testKeepMineBeforeAnyScanStillQueues() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        var mine = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        mine.kilometres = 60
        phone.write(mine)
        scan(phone, &state)
        _ = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        // No scan in between: the mark still holds the phone's own content.
        let kept = try XCTUnwrap(state.keepMine(siteID: hauptstrasse, date: the29th))
        phone.write(try XCTUnwrap(kept.day))
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.baseVersion), [2])
        XCTAssertEqual(state.queue.first?.data?["kilometres"]?.intValue, 60)
    }

    func testAnUnsentDeleteIsKeptAsMineToo() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        phone.delete(hauptstrasse, the29th)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.deleted), [true])

        _ = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        XCTAssertNotNil(phone.day(hauptstrasse, the29th), "the office's day is there")
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: the29th)?.mine, ConnectMine(day: nil))
        XCTAssertEqual(state.waitingCount, 0)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)

        let kept = try XCTUnwrap(state.keepMine(siteID: hauptstrasse, date: the29th))
        XCTAssertNil(kept.day)
        phone.delete(hauptstrasse, the29th)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.deleted), [true])
        XCTAssertEqual(state.queue.map(\.baseVersion), [2])
    }

    func testAnUnsentEditThatSaysTheSameIsNoConflict() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        // The team leader made the very correction the office made.
        let lukaRow = try XCTUnwrap(phone.row("Luka Babić", on: hauptstrasse))
        var mine = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        mine.present = mine.present.map { $0.memberID == lukaRow.id ? Attendance(memberID: lukaRow.id, end: TimeOfDay(hour: 12, minute: 0)) : $0 }
        mine.note = "Luka to the doctor at 12:00 (corrected by the office)."
        mine.allowanceMemberIDs = mine.present.map(\.memberID)
        phone.write(mine)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 1)

        // The office names the people in its own order.
        let plan = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        XCTAssertTrue(plan.siteDays.isEmpty, "nothing to write: the day says it already")
        XCTAssertEqual(phone.day(hauptstrasse, the29th), mine)
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: the29th)?.mine)
        XCTAssertNil(state.conflicts[key(hauptstrasse, the29th)])
        XCTAssertEqual(state.marks[key(hauptstrasse, the29th)]?.baseVersion, 2)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)
    }

    func testEditingTheOfficesCopyWhileAskedGoesOnFromIt() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        var mine = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        mine.note = "my own note"
        phone.write(mine)
        scan(phone, &state)
        _ = merge(try page("c1.1043", days: try fixture().siteDays), phone, &state)
        scan(phone, &state)

        var onTheirs = try XCTUnwrap(phone.day(hauptstrasse, the29th))
        onTheirs.kilometres = 50
        phone.write(onTheirs)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.baseVersion), [2])
        XCTAssertNil(state.conflicts[key(hauptstrasse, the29th)], "the choice was made by editing")
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: the29th))
    }

    // MARK: - The upload answered `conflict, editedOnWeb`

    func testAConflictOnUploadEndsInTheSamePlace() async throws {
        let stub = ConnectStubTransport.sample()
        let phone = Phone()
        let paired = try await ConnectSession.pair(
            client: ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub),
            code: "K7QF-3MZP", device: ConnectV1.DeviceInfo(name: "Phone", appVersion: "1.3"), now: now
        )
        let client = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token)
        var state = try await ConnectSession.receive(client: client, state: paired.state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })

        // A day, sent.
        let mine = SiteDay(
            siteID: hauptstrasse, date: today, start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 30), breakMinutes: 30,
            present: [Attendance(memberID: CrewMember.youID)] + phone.crew.map { Attendance(memberID: $0.id) }
        )
        phone.write(mine)
        scan(phone, &state)
        _ = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        let id = ConnectSiteDayRef(siteID: hauptstrasse, date: today).id
        XCTAssertEqual(stub.storedVersion(.siteDay, id), 1)

        // The office edits it; the phone, not having synced, edits it too
        // and sends.
        var theirs = try ConnectJSON.decode(ConnectV1.SiteDay.self, from: ConnectJSON.encode(try XCTUnwrap(stub.storedData(.siteDay, id))))
        theirs.note = "Ivan left at noon (office)"
        XCTAssertEqual(stub.writeOfficeDay(theirs), 2)
        var edited = mine
        edited.note = "we stayed late"
        phone.write(edited)
        scan(phone, &state)
        let report = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(report.conflicts.map(\.reason), ["editedOnWeb"])
        XCTAssertEqual(stub.storedVersion(.siteDay, id), 2, "an office edit is never overwritten by a phone that has not seen it")
        XCTAssertEqual(state.status(of: .siteDay, id: id), .changedByOffice)
        XCTAssertTrue(state.hasOfficeDaysToTake(lock: .unlocked))

        // The office's copy from the answer is taken, the phone's set aside.
        let pending = ConnectMerge.planPending(state: state, local: phone.local, lock: .unlocked)
        phone.apply(pending)
        state = pending.state
        XCTAssertEqual(phone.day(hauptstrasse, today)?.note, "Ivan left at noon (office)")
        XCTAssertEqual(phone.day(hauptstrasse, today)?.present.count, 3)
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: today)?.mine?.day, edited)
        XCTAssertFalse(state.hasOfficeDaysToTake(lock: .unlocked))
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)

        // The sync that brings the same edit changes nothing more.
        state = try await ConnectSession.receive(client: client, state: state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: today)?.mine?.day, edited)
        XCTAssertEqual(phone.day(hauptstrasse, today)?.note, "Ivan left at noon (office)")

        // Keep mine: sent again on the office's version, and it wins.
        let kept = try XCTUnwrap(state.keepMine(siteID: hauptstrasse, date: today)?.day)
        phone.write(kept)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.baseVersion), [2])
        let again = await ConnectSession.send(client: client, state: &state, now: { self.now }, jitter: { 0.5 }, fileBytes: { _ in nil })
        XCTAssertEqual(again.accepted, 1)
        XCTAssertEqual(stub.storedVersion(.siteDay, id), 3)
        XCTAssertEqual(stub.storedData(.siteDay, id)?["note"]?.stringValue, "we stayed late")
        XCTAssertEqual(state.status(of: .siteDay, id: id), .sent)
    }

    func testAnOfficeDayArrivesThroughTheStubAndIsDeletedAgain() async throws {
        let stub = ConnectStubTransport.sample(officeDayOn: today)
        let phone = Phone()
        let paired = try await ConnectSession.pair(
            client: ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub),
            code: "K7QF-3MZP", device: ConnectV1.DeviceInfo(name: "Phone", appVersion: "1.3"), now: now
        )
        let client = ConnectClient(baseURL: ConnectStubTransport.baseURL, transport: stub, token: paired.token)
        var state = try await ConnectSession.receive(client: client, state: paired.state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        let day = try XCTUnwrap(phone.day(hauptstrasse, today), "the office's day is on the site after the first sync")
        XCTAssertEqual(day.present.count, 3)
        XCTAssertTrue(day.present.contains { $0.memberID == CrewMember.youID })
        XCTAssertEqual(state.officeDay(siteID: hauptstrasse, date: today)?.mark, .written)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0)

        stub.deleteOfficeDay(ConnectSiteDayRef(siteID: hauptstrasse, date: today).id)
        state = try await ConnectSession.receive(client: client, state: state, lock: .unlocked, today: today, now: now, local: { phone.local }, apply: { phone.apply($0) })
        XCTAssertNil(phone.day(hauptstrasse, today))
        XCTAssertNil(state.officeDay(siteID: hauptstrasse, date: today))
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 0, "no delete is sent for a day the office deleted")
    }

    // MARK: - A deleted office day

    func testATombstoneDeletesOnlyWhatTheOfficeWroteAndThePhoneLeftAlone() throws {
        let (phone, start) = try paired()
        var state = start
        _ = try withASentDay(phone, &state)
        _ = merge(try page("c1.1043", days: try officeDays()), phone, &state)
        scan(phone, &state)
        let the24th = CalendarDate(year: 2026, month: 10, day: 24)
        XCTAssertEqual(phone.days.count, 3)

        // The 24th has an unsent local edit.
        var edited = try XCTUnwrap(phone.day(schule, the24th))
        edited.note = "we did work that Saturday"
        phone.write(edited)
        scan(phone, &state)
        XCTAssertEqual(state.waitingCount, 1)

        let ids = [the17th, the24th].map { ConnectSiteDayRef(siteID: schule, date: $0).id } + [ConnectSiteDayRef(siteID: hauptstrasse, date: the29th).id]
        let plan = merge(try page("c1.1044", tombstones: ids), phone, &state)
        XCTAssertEqual(plan.removedSiteDays, [ConnectSiteDayRef(siteID: schule, date: the17th)])
        XCTAssertNil(phone.day(schule, the17th), "office-written, untouched by the phone: deleted")
        XCTAssertEqual(phone.day(schule, the24th), edited, "an unsent local edit keeps the day")
        XCTAssertNotNil(phone.day(hauptstrasse, the29th), "a phone's day the office edited is never deleted")
        XCTAssertNil(state.marks[key(schule, the17th)])
        XCTAssertEqual(state.waitingCount, 1)
        scan(phone, &state)
        XCTAssertEqual(state.queue.map(\.deleted), [false], "and no delete goes back for the day the office deleted")
        XCTAssertEqual(state.officeMarks(siteID: schule), [:])
    }

    func testATombstoneWhileAskedMakesThePhonesEditTheDayAgain() throws {
        let (phone, start) = try paired()
        var state = start
        _ = merge(try page("c1.1043", days: try officeDays().filter(\.isOfficeWritten)), phone, &state)
        scan(phone, &state)
        var mine = try XCTUnwrap(phone.day(schule, the17th))
        mine.note = "mine"
        phone.write(mine)
        scan(phone, &state)
        var newer = try XCTUnwrap(try officeDays().first)
        newer.version = 2
        newer.note = "the office again"
        _ = merge(try page("c1.1044", days: [newer]), phone, &state)
        XCTAssertEqual(state.officeDay(siteID: schule, date: the17th)?.mine?.day, mine)

        _ = merge(try page("c1.1045", tombstones: [ConnectSiteDayRef(siteID: schule, date: the17th).id]), phone, &state)
        XCTAssertEqual(phone.day(schule, the17th), mine)
        XCTAssertNil(state.officeDay(siteID: schule, date: the17th))
        XCTAssertNil(state.conflicts[key(schule, the17th)])
        scan(phone, &state)
        XCTAssertEqual(state.queue.first?.data?["note"]?.stringValue, "mine")
    }

    func testATombstoneInAClosedMonthWaitsForIt() throws {
        let (phone, start) = try paired()
        var state = start
        _ = merge(try page("c1.1043", days: try officeDays().filter(\.isOfficeWritten)), phone, &state)
        scan(phone, &state)
        let closed = MonthLock(months: [october])
        let id = ConnectSiteDayRef(siteID: schule, date: the17th).id

        let plan = merge(try page("c1.1044", tombstones: [id]), phone, &state, lock: closed)
        XCTAssertTrue(plan.removedSiteDays.isEmpty)
        XCTAssertNotNil(phone.day(schule, the17th))
        XCTAssertEqual(plan.conflicts.map(\.kind), [.officeDayInClosedMonth])
        XCTAssertTrue(merge(try page("c1.1045"), phone, &state, lock: closed).conflicts.isEmpty, "listed once")

        let reopened = merge(try page("c1.1046"), phone, &state)
        XCTAssertEqual(reopened.removedSiteDays, [ConnectSiteDayRef(siteID: schule, date: the17th)])
        XCTAssertNil(phone.day(schule, the17th))
        XCTAssertTrue(state.heldOfficeDays.isEmpty)
    }

    // MARK: - One day, field by field

    func testADayIsReadFieldByField() throws {
        let other = UUID()
        let moveID = UUID()
        let rowA = UUID()
        let rowB = UUID()
        let ids = ["a": rowA, "b": rowB, "you": CrewMember.youID]
        let job = UUID()
        let mineMove = SiteMove(
            id: moveID, toSiteID: other, left: TimeOfDay(hour: 11, minute: 30), started: TimeOfDay(hour: 12, minute: 0), breakPlacement: .split,
            people: [SiteMove.Person(memberID: rowA, targetMemberID: UUID(), before: Attendance(memberID: rowA), targetAllowanceBefore: true)],
            createdTargetDay: true
        )
        let existing = SiteDay(siteID: hauptstrasse, date: the29th, jobID: job, moves: [mineMove])
        let newMove = UUID()
        let wire = ConnectV1.SiteDay(
            id: ConnectSiteDayRef(siteID: hauptstrasse, date: the29th).id,
            siteId: ConnectID.string(hauptstrasse),
            date: "2026-10-29",
            start: "07:00",
            end: nil,
            breakMinutes: 45,
            attendance: [
                ConnectV1.Attendance(memberId: "a", start: "08:00", end: "11:30", breakMinutes: 15),
                ConnectV1.Attendance(memberId: "a"),
                ConnectV1.Attendance(memberId: "nobody"),
            ],
            absences: [
                ConnectV1.Absence(memberId: "b", reason: ConnectV1.AbsenceReason(type: "dayType", dayType: "sick", siteId: nil)),
                ConnectV1.Absence(memberId: "you", reason: ConnectV1.AbsenceReason(type: "otherSite", dayType: nil, siteId: ConnectID.string(other))),
                ConnectV1.Absence(memberId: "a", reason: ConnectV1.AbsenceReason(type: "dayType", dayType: "vacation", siteId: nil)),
                ConnectV1.Absence(memberId: "b", reason: ConnectV1.AbsenceReason(type: "somethingNew", dayType: nil, siteId: nil)),
            ],
            noWork: nil,
            badWeatherStop: true,
            note: "note",
            allowanceMemberIds: ["a", "b", "a"],
            kilometres: 12,
            moves: [
                ConnectV1.SiteMove(id: ConnectID.string(moveID), toSiteId: ConnectID.string(other), left: "11:30", started: "12:00", breakPlacement: "split", memberIds: ["a"]),
                ConnectV1.SiteMove(id: ConnectID.string(newMove), toSiteId: ConnectID.string(other), left: "13:00", started: "13:20", breakPlacement: "somewhere", memberIds: ["b", "nobody"]),
            ],
            updatedAt: "2026-11-02T08:20:00Z"
        )
        let day = ConnectIncoming.siteDay(wire, siteID: hauptstrasse, date: the29th, existing: existing, jobID: UUID()) { ids[$0] }
        XCTAssertEqual(day.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertNil(day.end)
        XCTAssertEqual(day.breakMinutes, 45)
        XCTAssertEqual(day.present, [Attendance(memberID: rowA, start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 11, minute: 30), breakMinutes: 15)])
        XCTAssertEqual(day.absences, [
            CrewAbsence(memberID: rowB, dayTypeID: DayTypeID("sick")),
            CrewAbsence(memberID: CrewMember.youID, reason: .otherSite(other)),
        ], "someone present is not away, and an unknown reason is left out")
        XCTAssertTrue(day.isBadWeatherStop)
        XCTAssertEqual(day.allowanceMemberIDs, [rowA], "only for someone present, once")
        XCTAssertEqual(day.kilometres, 12)
        XCTAssertEqual(day.jobID, job, "the job the phone froze stays")
        XCTAssertEqual(day.moves.first, mineMove, "the phone's own move keeps what Undo needs")
        XCTAssertEqual(day.moves.last?.memberIDs, [rowB])
        XCTAssertEqual(day.moves.last?.breakPlacement, .here)
        XCTAssertEqual(day.moves.last?.left, TimeOfDay(hour: 13, minute: 0))

        var none = wire
        none.attendance = []
        none.absences = []
        none.badWeatherStop = false
        none.noWork = "dayOff"
        let noWork = ConnectIncoming.siteDay(none, siteID: hauptstrasse, date: the29th, existing: nil, jobID: job) { ids[$0] }
        XCTAssertEqual(noWork.noWork, .dayOff)
        XCTAssertEqual(noWork.jobID, job, "a new day counts towards the site's job")
        none.noWork = "aNewReason"
        XCTAssertNil(ConnectIncoming.siteDay(none, siteID: hauptstrasse, date: the29th, existing: nil, jobID: nil) { ids[$0] }.noWork)
    }

    // MARK: - The state file

    func testAStateFileFromBeforeOfficeDaysStillReads() throws {
        var old = ConnectState()
        old.marks["siteDay:x"] = ConnectRecordMark(version: 3, baseVersion: 2, hash: "abc", siteIDs: [hauptstrasse], month: october)
        var json = try ConnectJSON.decode(JSONValue.self, from: JSONEncoder().encode(old))
        if case var .object(object) = json {
            object["officeDays"] = nil
            object["heldOfficeDays"] = nil
            json = .object(object)
        }
        let text = String(decoding: try ConnectJSON.encode(json), as: UTF8.self)
        XCTAssertFalse(text.contains("adopts"), "an unset flag is not written")
        let read = try JSONDecoder().decode(ConnectState.self, from: Data(text.utf8))
        XCTAssertEqual(read.marks["siteDay:x"]?.version, 3)
        XCTAssertTrue(read.officeDays.isEmpty)
        XCTAssertTrue(read.heldOfficeDays.isEmpty)
    }
}
