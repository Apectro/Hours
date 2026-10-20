import XCTest
import SwiftData
@testable import Hours

/// Backing up and restoring sites, and the calendar shifts that come from them.
///
/// The failures these exist to catch: an old backup wiping sites it never
/// knew about, a new one failing to replace them, and the calendar keeping
/// site hours that no site day backs (or missing ones that do).
@MainActor
final class SiteRestoreTests: XCTestCase {
    private let date = Fixture.workingTuesday
    private let site = Site(name: "Hauptstraße 12", jobID: UUID())
    private let ivan = UUID()

    private func makeContext() -> ModelContext {
        ModelContext(HoursModelContainer.ephemeral())
    }

    private func crewDay(for site: Site? = nil, on date: CalendarDate? = nil, withYou: Bool = true) -> SiteDay {
        let site = site ?? self.site
        var present = [Attendance(memberID: ivan)]
        if withYou { present.insert(Attendance(memberID: CrewMember.youID), at: 0) }
        return SiteDay(
            siteID: site.id,
            date: date ?? self.date,
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present,
            jobID: site.jobID
        )
    }

    private func siteShifts(_ record: DayRecord?) -> [Shift] {
        record?.shifts.filter { $0.siteID != nil } ?? []
    }

    private func populate(_ context: ModelContext) throws {
        let sites = SiteRepository(context: context)
        sites.upsert(site)
        sites.upsert(CrewMember(id: ivan, siteID: site.id, name: "Ivan", isHidden: true))
        try sites.save(crewDay())
    }

    // MARK: - Backing up

    func testBackupCarriesSitesCrewAndSiteDaysIncludingHiddenAndArchived() throws {
        let context = makeContext()
        try populate(context)
        SiteRepository(context: context).upsert(Site(name: "Old", isArchived: true))

        let archive = BackupRestorer(context: context).makeArchive(settings: Fixture.settings())

        XCTAssertEqual(archive.sites?.count, 2)
        XCTAssertEqual(archive.crew?.map(\.name), ["Ivan"], "hidden members are part of the history")
        XCTAssertEqual(archive.siteDays?.count, 1)
    }

    func testBackupOfAnEmptyStoreSaysItKnowsAboutSites() {
        let archive = BackupRestorer(context: makeContext()).makeArchive(settings: Fixture.settings())

        XCTAssertEqual(archive.sites, [])
        XCTAssertEqual(archive.crew, [])
        XCTAssertEqual(archive.siteDays, [])
    }

    func testABackupRoundTripsThroughRestore() throws {
        let source = makeContext()
        try populate(source)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))

        let repository = SiteRepository(context: target)
        XCTAssertEqual(repository.sites(includeArchived: true), [site])
        XCTAssertEqual(repository.crew(for: site.id, includeHidden: true).map(\.name), ["Ivan"])
        XCTAssertEqual(repository.siteDays(siteID: nil, in: CalendarDateRange(single: date)).count, 1)
        XCTAssertEqual(siteShifts(WorkdayRepository(context: target).record(on: date)).count, 1)
    }

    // MARK: - Restoring

    func testRestoringOldBackupKeepsSites() throws {
        let context = makeContext()
        try populate(context)
        let other = Fixture.date(2026, 8, 5)
        let old = BackupArchive(
            settings: Fixture.settings(),
            days: [DayRecord(date: other, shifts: [Shift(start: Fixture.time(9), end: Fixture.time(10))])],
            holidays: []
        )
        XCTAssertNil(old.sites)

        BackupRestorer(context: context).restore(old)

        let sites = SiteRepository(context: context)
        XCTAssertEqual(sites.sites(includeArchived: true), [site])
        XCTAssertEqual(sites.crew(for: site.id, includeHidden: true).count, 1)
        XCTAssertEqual(sites.siteDays(siteID: nil, in: CalendarDateRange(single: date)).count, 1)

        let workdays = WorkdayRepository(context: context)
        XCTAssertNotNil(workdays.record(on: other), "the file's own day is restored")
        XCTAssertEqual(siteShifts(workdays.record(on: date)).count, 1,
                       "the site day still on the device is put back into the calendar")
    }

    func testRestoringNewBackupReplacesSites() throws {
        let context = makeContext()
        try populate(context)
        let replacement = Site(name: "Bahnhof")
        let member = CrewMember(siteID: replacement.id, name: "Marta")
        let day = crewDay(for: replacement, on: Fixture.date(2026, 8, 5))
        let archive = BackupArchive(
            settings: Fixture.settings(),
            days: [],
            holidays: [HolidayRule(name: "Feiertag", recurrence: .once(on: Fixture.date(2026, 12, 25)))],
            sites: [replacement],
            crew: [member],
            siteDays: [day]
        )

        BackupRestorer(context: context).restore(archive)

        let sites = SiteRepository(context: context)
        XCTAssertEqual(sites.sites(includeArchived: true), [replacement])
        XCTAssertEqual(sites.crew(for: replacement.id, includeHidden: true), [member])
        XCTAssertTrue(sites.crew(for: site.id, includeHidden: true).isEmpty)
        XCTAssertEqual(sites.siteDays(siteID: nil, in: CalendarDateRange(start: date, end: Fixture.date(2026, 8, 31))), [day])
    }

    func testAnEmptyListOfSitesReplacesThemToo() throws {
        let context = makeContext()
        try populate(context)
        let archive = BackupArchive(
            settings: Fixture.settings(),
            days: [DayRecord(date: date, note: "x")],
            holidays: [],
            sites: [], crew: [], siteDays: []
        )

        BackupRestorer(context: context).restore(archive)

        XCTAssertTrue(SiteRepository(context: context).sites(includeArchived: true).isEmpty)
        XCTAssertTrue(siteShifts(WorkdayRepository(context: context).record(on: date)).isEmpty)
    }

    func testRestoreRebuildsCalendarSiteShifts() throws {
        let context = makeContext()
        let phantom = Shift(id: UUID(), start: Fixture.time(6), end: Fixture.time(9), siteID: UUID())
        let manual = Shift(start: Fixture.time(18), end: Fixture.time(20))
        let wrong = DayRecord(date: date, shifts: [manual, phantom], note: "kept")
        let onlyPhantom = DayRecord(date: Fixture.date(2026, 8, 6), shifts: [phantom])
        let archive = BackupArchive(
            settings: Fixture.settings(),
            // The file's calendar shows no shift for the real site day on
            // Aug 5, a shift for a site that is not in the file on Aug 4, and
            // a day on Aug 6 made of nothing else.
            days: [wrong, onlyPhantom],
            holidays: [],
            sites: [site],
            crew: [],
            siteDays: [crewDay(on: Fixture.date(2026, 8, 5))]
        )

        BackupRestorer(context: context).restore(archive)

        let workdays = WorkdayRepository(context: context)
        let tuesday = workdays.record(on: date)
        XCTAssertTrue(siteShifts(tuesday).isEmpty, "a site shift whose site is not present is dropped")
        XCTAssertEqual(tuesday?.shifts, [manual])
        XCTAssertEqual(tuesday?.note, "kept")
        XCTAssertNil(workdays.record(on: Fixture.date(2026, 8, 6)), "a day left blank is deleted")
        XCTAssertEqual(siteShifts(workdays.record(on: Fixture.date(2026, 8, 5))).first?.siteID, site.id)
    }

    func testRestoreWritesIntoClosedMonths() throws {
        let context = makeContext()
        let archive = BackupArchive(
            settings: Fixture.settings(),
            days: [],
            holidays: [],
            sites: [site],
            crew: [],
            siteDays: [crewDay()]
        )

        BackupRestorer(context: context).restore(archive)

        XCTAssertEqual(siteShifts(WorkdayRepository(context: context).record(on: date)).count, 1)
    }

    // MARK: - Deleting everything

    func testDeleteEverythingRemovesSitesCrewAndSiteDaysToo() throws {
        let context = makeContext()
        try populate(context)

        BackupRestorer(context: context).deleteEverything()

        let sites = SiteRepository(context: context)
        XCTAssertTrue(sites.sites(includeArchived: true).isEmpty)
        XCTAssertTrue(sites.crew(for: site.id, includeHidden: true).isEmpty)
        XCTAssertTrue(sites.siteDays(siteID: nil, in: CalendarDateRange(single: date)).isEmpty)
        XCTAssertNil(WorkdayRepository(context: context).record(on: date))
    }
}
