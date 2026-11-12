import XCTest
@testable import Hours

/// Receiving: a sync page merged into the phone's sites and crews, who is
/// who, and what a closed month stops.
final class ConnectMergeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_611_800)
    private let today = CalendarDate(year: 2026, month: 11, day: 2)
    private let hauptstrasse = UUID(uuidString: "a2364fc3-f9d6-51dc-9eb9-41868669e10f")!
    private let schule = UUID(uuidString: "d65be387-0478-5071-8e5c-052d65e0fb8b")!
    private let marko = UUID(uuidString: "0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11")!
    private let ivan = UUID(uuidString: "eabdee49-f0eb-575b-9032-773c56337457")!

    private func fixture() throws -> ConnectV1.SyncResponse {
        try ConnectFixtures.decode(ConnectV1.SyncResponse.self, "device.sync.response")
    }

    private func pairedState() -> ConnectState {
        var state = ConnectState()
        state.people.you = marko
        return state
    }

    // MARK: - Creating

    func testAFullSnapshotMakesTheSitesAndCrews() throws {
        let plan = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(Set(plan.sites.map(\.id)), [hauptstrasse, schule])
        let site = try XCTUnwrap(plan.sites.first { $0.id == hauptstrasse })
        XCTAssertEqual(site.name, "Hauptstraße 12")
        XCTAssertEqual(site.address, "Hauptstraße 12\n1040 Wien")
        XCTAssertTrue(site.allowanceByDefault)
        XCTAssertEqual(plan.state.companySites, [hauptstrasse, schule])

        let setup = try XCTUnwrap(plan.setups[hauptstrasse])
        XCTAssertEqual(setup.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(setup.end, TimeOfDay(hour: 15, minute: 30))
        XCTAssertEqual(setup.breakMinutes, 30)
        XCTAssertEqual(setup.workDays, [2, 3, 4, 5, 6])

        // The paired person is You and gets no row; Ivan is on both sites,
        // one row each, both him.
        let rows = plan.crew.filter { $0.siteID == hauptstrasse }
        XCTAssertEqual(rows.map(\.name).sorted(), ["Ivan Horvat", "Luka Babić"])
        let ivanRows = plan.crew.filter { plan.state.people.rows[$0.id] == ivan }
        XCTAssertEqual(Set(ivanRows.map(\.siteID)), [hauptstrasse, schule])
        XCTAssertEqual(Set(ivanRows.map(\.id)).count, 2)
        // His assignment on the school ended on 31 October: hidden there.
        XCTAssertEqual(ivanRows.first { $0.siteID == schule }?.isHidden, true)
        XCTAssertEqual(ivanRows.first { $0.siteID == hauptstrasse }?.isHidden, false)

        XCTAssertEqual(plan.state.cursor, "c1.1042")
        XCTAssertEqual(plan.state.lastSyncedAt, now)
        XCTAssertEqual(plan.state.comments.count, 2)
        XCTAssertEqual(plan.state.reviews[ConnectRecordKey.make(.sheet, "490ac112-e922-5f2a-98da-81144aa5d13e")]?.state, "returned")
    }

    func testRowsAreTheSameOnEveryPhone() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        let second = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(first.crew.map(\.id).sorted { $0.uuidString < $1.uuidString }, second.crew.map(\.id).sorted { $0.uuidString < $1.uuidString })
    }

    // MARK: - Matching what the phone has

    func testAnExistingRowOfTheSameNameIsLinkedNotDoubled() throws {
        let site = Site(id: hauptstrasse, name: "Hauptstrasse 12", sortOrder: 3, remindsOnArrival: true)
        let local = CrewMember(siteID: hauptstrasse, name: "  ivan  horvat", sortOrder: 0)
        let plan = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [site], crew: [local]), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(plan.state.people.rows[local.id], ivan, "matched by name the way crews are joined")
        XCTAssertFalse(plan.crew.contains { $0.siteID == hauptstrasse && $0.id != local.id && $0.name == "Ivan Horvat" })
        XCTAssertEqual(plan.crew.first { $0.id == local.id }?.name, "Ivan Horvat", "the web's spelling")

        // The web's name and address; the phone's own settings stay.
        let merged = try XCTUnwrap(plan.sites.first { $0.id == hauptstrasse })
        XCTAssertEqual(merged.name, "Hauptstraße 12")
        XCTAssertEqual(merged.sortOrder, 3)
        XCTAssertTrue(merged.remindsOnArrival)
    }

    func testALocalRenameIsOverwrittenAtTheNextSync() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        var renamed = try XCTUnwrap(first.sites.first { $0.id == hauptstrasse })
        renamed.name = "My name for it"
        let empty = ConnectV1.SyncResponse(cursor: "c1.1043", hasMore: false, full: false, serverTime: "", company: try fixture().company)
        let next = ConnectMerge.plan(empty, state: first.state, local: ConnectLocal(sites: first.sites.filter { $0.id != hauptstrasse } + [renamed], crew: first.crew), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(next.sites.map(\.name), ["Hauptstraße 12"])
        XCTAssertTrue(next.crew.isEmpty, "nothing else changed")
    }

    // MARK: - Who is who

    func testLinkingByNameAndToItself() {
        var people = ConnectPeople()
        people.you = marko
        people.company[ivan] = ConnectPeople.ConnectPerson(name: "Ivan Horvat", hidden: false)
        let onWebSite = CrewMember(siteID: hauptstrasse, name: "Ivan Horvat")
        let newHere = CrewMember(siteID: hauptstrasse, name: "Ante")
        let anteElsewhere = CrewMember(siteID: schule, name: "ante ")
        let linked = people.linking([onWebSite, newHere, anteElsewhere])
        XCTAssertEqual(linked.rows[onWebSite.id], ivan)
        let ante = linked.rows[newHere.id]
        XCTAssertNotNil(ante)
        XCTAssertEqual(linked.rows[anteElsewhere.id], ante, "the same name on two sites is one person")
        XCTAssertTrue(ante == newHere.id || ante == anteElsewhere.id, "a person added on the phone is the row's own id")
        XCTAssertEqual(linked.outgoing(CrewMember.youID), marko, "You is the paired person")
        XCTAssertNil(ConnectPeople().outgoing(CrewMember.youID), "never the fixed You id")
        // Linked rows keep their person.
        var relinked = linked
        relinked.company[ivan] = nil
        XCTAssertEqual(relinked.linking([onWebSite]).rows[onWebSite.id], ivan)
    }

    // MARK: - Updates and removals

    func testIncrementalUpdatesRenameAndHide() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        var page = ConnectV1.SyncResponse(cursor: "c1.1050", hasMore: false, full: false, serverTime: "", company: try fixture().company)
        page.crew = [ConnectStubTransport.person(ConnectID.string(ivan), "Ivan Horvat-Kovač")]
        page.crew[0].hidden = true
        let next = ConnectMerge.plan(page, state: first.state, local: ConnectLocal(sites: first.sites, crew: first.crew), lock: .unlocked, today: today, now: now)
        let rows = next.crew.filter { next.state.people.rows[$0.id] == ivan }
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.name == "Ivan Horvat-Kovač" && $0.isHidden })
        XCTAssertEqual(next.state.cursor, "c1.1050")
    }

    func testTombstonesArchiveAndHideNeverDelete() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        var page = ConnectV1.SyncResponse(cursor: "c1.1060", hasMore: false, full: false, serverTime: "", company: try fixture().company)
        page.tombstones = [
            ConnectV1.Tombstone(kind: .site, id: ConnectID.string(schule), deletedAt: ""),
            ConnectV1.Tombstone(kind: .assignment, id: "28e27f54-4818-53f1-9643-412a4d57a2f0", deletedAt: ""),
            ConnectV1.Tombstone(kind: .comment, id: "59d760de-aed9-5bc2-8bdd-48161c99449a", deletedAt: ""),
        ]
        let next = ConnectMerge.plan(page, state: first.state, local: ConnectLocal(sites: first.sites, crew: first.crew), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(next.sites.map(\.id), [schule])
        XCTAssertEqual(next.sites.first?.isArchived, true, "archived, with its days")
        let ivanHere = next.crew.first { $0.siteID == hauptstrasse && next.state.people.rows[$0.id] == ivan }
        XCTAssertEqual(ivanHere?.isHidden, true, "off the site: hidden, his days kept")
        XCTAssertNil(next.state.comments["59d760de-aed9-5bc2-8bdd-48161c99449a"])
        XCTAssertTrue(next.conflicts.isEmpty)
    }

    func testAFullSnapshotRemovesWhatItNoLongerHolds() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        var snapshot = try fixture()
        snapshot.sites.removeAll { $0.id == ConnectID.string(schule) }
        snapshot.assignments.removeAll { $0.siteId == ConnectID.string(schule) }
        snapshot.cursor = "c1.2000"
        // Two pages: the removal waits for the last.
        var firstPage = snapshot
        firstPage.hasMore = true
        firstPage.sites = []
        let middle = ConnectMerge.plan(firstPage, state: first.state, local: ConnectLocal(sites: first.sites, crew: first.crew), lock: .unlocked, today: today, now: now)
        XCTAssertFalse(middle.sites.contains { $0.isArchived })
        var lastPage = snapshot
        lastPage.full = false
        lastPage.crew = []
        lastPage.assignments = []
        let last = ConnectMerge.plan(lastPage, state: middle.state, local: ConnectLocal(sites: first.sites, crew: first.crew), lock: .unlocked, today: today, now: now)
        XCTAssertEqual(last.sites.filter(\.isArchived).map(\.id), [schule])
        XCTAssertNil(last.state.snapshot)
    }

    // MARK: - Closed months

    func testAClosedMonthIsNeverChangedAndIsListed() throws {
        let first = ConnectMerge.plan(try fixture(), state: pairedState(), local: ConnectLocal(sites: [], crew: []), lock: .unlocked, today: today, now: now)
        var state = first.state
        // The October sheet was sent from here.
        let sheetKey = ConnectRecordKey.make(.sheet, "490ac112-e922-5f2a-98da-81144aa5d13e")
        state.marks[sheetKey] = ConnectRecordMark(version: 1, baseVersion: 0, hash: "h", siteIDs: [hauptstrasse, schule], month: YearMonth(year: 2026, month: 10))
        state.reviews = [:]
        var lock = MonthLock()
        lock.lock(YearMonth(year: 2026, month: 10))
        let october = Set((1...31).map { CalendarDate(year: 2026, month: 10, day: $0) })

        var page = try fixture()
        page.full = false
        page.tombstones = [ConnectV1.Tombstone(kind: .site, id: ConnectID.string(schule), deletedAt: "")]
        let plan = ConnectMerge.plan(page, state: state, local: ConnectLocal(sites: first.sites, crew: first.crew, writtenDates: [hauptstrasse: october, schule: october]), lock: lock, today: today, now: now)
        XCTAssertEqual(Set(plan.conflicts.map(\.kind)), [.returnedInClosedMonth, .siteRemovedWithClosedMonth])
        XCTAssertEqual(Set(plan.conflicts.map(\.month)), ["2026-10"])
        XCTAssertEqual(plan.state.lockedConflicts.count, 2)
        XCTAssertEqual(plan.state.marks[sheetKey]?.baseVersion, 2, "the review's version is the base for a correction")
        // Archived all the same; nothing about a day is in the plan at all.
        XCTAssertEqual(plan.sites.first { $0.id == schule }?.isArchived, true)
    }
}
