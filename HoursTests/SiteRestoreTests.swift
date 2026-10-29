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

    /// The arrival reminder's place, radius and switch live on `SiteEntry`,
    /// and a restore rebuilds entries from `Site`: they must travel both ways.
    func testTheArrivalPlaceRoundTripsThroughBackupAndRestore() throws {
        let source = makeContext()
        var placed = Site(name: "Trg Pravde", sortOrder: 1)
        placed.place = SitePlace(latitude: 45.8150, longitude: 15.9819)
        placed.arrivalRadius = 300
        placed.remindsOnArrival = true
        SiteRepository(context: source).upsert(placed)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        SiteRepository(context: target).upsert(Site(name: "Wiped by the restore"))
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))

        let restored = try XCTUnwrap(SiteRepository(context: target).site(id: placed.id))
        XCTAssertEqual(restored, placed)
        XCTAssertEqual(restored.place, SitePlace(latitude: 45.8150, longitude: 15.9819))
        XCTAssertEqual(restored.arrivalRadius, 300)
        XCTAssertTrue(restored.remindsOnArrival)
        let entry = try XCTUnwrap(target.fetch(FetchDescriptor<SiteEntry>()).first { $0.siteID == placed.id.uuidString })
        XCTAssertEqual(entry.latitude, 45.8150)
        XCTAssertEqual(entry.longitude, 15.9819)
        XCTAssertEqual(entry.arrivalRadius, 300)
        XCTAssertTrue(entry.remindsOnArrival)
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
        let august = YearMonth(year: date.year, month: date.month)
        let closedAugust = MonthLock(months: [august])
        let personal = DayRecord(date: Fixture.date(2026, 8, 5), note: "closed but restored")

        // The month really is closed: ordinary writes on this context refuse.
        XCTAssertThrowsError(try WorkdayRepository(context: context, lock: closedAugust).save(personal)) {
            XCTAssertEqual($0 as? MonthLock.Refusal, .monthIsClosed(august))
        }
        XCTAssertThrowsError(try SiteRepository(context: context, lock: closedAugust).save(crewDay())) {
            XCTAssertEqual($0 as? MonthLock.Refusal, .monthIsClosed(august))
        }

        var settings = Fixture.settings()
        settings.monthLock = closedAugust
        let archive = BackupArchive(
            settings: settings,
            days: [personal],
            holidays: [],
            sites: [site],
            crew: [],
            siteDays: [crewDay()]
        )

        // The live lock is handed over and must be ignored.
        BackupRestorer(context: context, liveLock: closedAugust).restore(archive)

        let workdays = WorkdayRepository(context: context)
        XCTAssertEqual(workdays.record(on: personal.date)?.note, "closed but restored")
        XCTAssertEqual(siteShifts(workdays.record(on: date)).count, 1)
        XCTAssertEqual(SiteRepository(context: context).siteDays(siteID: nil, in: CalendarDateRange(single: date)).count, 1)
    }

    // MARK: - The guard

    func testAFileHoldingOnlySitesIsWorthRestoring() {
        let onlySites = BackupArchive(settings: Fixture.settings(), days: [], holidays: [], sites: [site])
        XCTAssertTrue(BackupRestorer.hasAnythingToRestore(onlySites))
    }

    func testTrulyEmptyFilesAreNotWorthRestoring() {
        XCTAssertFalse(BackupRestorer.hasAnythingToRestore(
            BackupArchive(settings: Fixture.settings(), days: [], holidays: [])))
        XCTAssertFalse(BackupRestorer.hasAnythingToRestore(
            BackupArchive(settings: Fixture.settings(), days: [], holidays: [], sites: [], crew: [], siteDays: [])))
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

    // MARK: - The diary, its photos and signatures

    private func populateDiary(_ context: ModelContext) {
        let diary = SiteDiaryRepository(context: context)
        diary.store(SiteDiary(siteID: site.id, date: date, weather: .rain, workDone: "Formwork"))
        diary.addPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]), siteID: site.id, on: date)
        diary.storeSignature(CrewSignature(
            siteID: site.id, memberID: ivan, month: date.yearMonth, signedOn: date,
            fingerprint: "v1:x", strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]
        ))
    }

    func testTheDiaryPhotosAndSignaturesRoundTripThroughRestore() throws {
        let source = makeContext()
        try populate(source)
        populateDiary(source)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))

        let diary = SiteDiaryRepository(context: target)
        XCTAssertEqual(diary.diary(siteID: site.id, on: date)?.workDone, "Formwork")
        XCTAssertEqual(diary.photos(siteID: site.id, on: date).map(\.jpegData), [Data([0xFF, 0xD8, 0xFF, 0xD9])])
        XCTAssertEqual(diary.signatures(siteID: site.id, month: date.yearMonth).count, 1)
    }

    func testABackupFromBeforeTheDiaryKeepsTheDiaryOfSitesItRestores() throws {
        let context = makeContext()
        try populate(context)
        populateDiary(context)
        let old = BackupArchive(settings: Fixture.settings(), days: [], holidays: [], sites: [site], crew: [], siteDays: [])

        BackupRestorer(context: context).restore(old)

        XCTAssertNotNil(SiteDiaryRepository(context: context).diary(siteID: site.id, on: date))
    }

    func testDeleteEverythingTakesTheDiaryWithTheSites() throws {
        let context = makeContext()
        try populate(context)
        populateDiary(context)

        BackupRestorer(context: context).deleteEverything()

        let diary = SiteDiaryRepository(context: context)
        XCTAssertNil(diary.diary(siteID: site.id, on: date))
        XCTAssertTrue(diary.photos(siteID: site.id, on: date).isEmpty)
        XCTAssertTrue(diary.signatures(siteID: site.id, month: date.yearMonth).isEmpty)
    }

    func testABlankDiaryStoresNothing() {
        let context = makeContext()
        let diary = SiteDiaryRepository(context: context)
        diary.store(SiteDiary(siteID: site.id, date: date, workDone: "x"))
        diary.store(SiteDiary(siteID: site.id, date: date))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteDiaryEntry>()), 0)
    }

    func testADayTakesNoMoreThanSixPhotos() {
        let diary = SiteDiaryRepository(context: makeContext())
        for _ in 0..<6 { XCTAssertTrue(diary.addPhoto(Data([1]), siteID: site.id, on: date)) }
        XCTAssertFalse(diary.addPhoto(Data([1]), siteID: site.id, on: date))
        XCTAssertEqual(diary.photos(siteID: site.id, on: date).map(\.sortOrder), [0, 1, 2, 3, 4, 5])
    }

    /// The repository half of a rained-off day: the type goes on your day
    /// with the stop, and comes off when the stop is lifted.
    func testLiftingAStopInTheRepositoryTakesTheBadWeatherTypeOff() throws {
        let context = makeContext()
        let sites = SiteRepository(context: context)
        sites.upsert(site)
        let stopped = crewDay().stoppedForBadWeather(at: nil)
        try sites.save(stopped)
        XCTAssertEqual(WorkdayRepository(context: context).record(on: date)?.dayTypeID, .badWeather)

        try sites.save(stopped.liftingBadWeatherStop())
        XCTAssertNil(WorkdayRepository(context: context).record(on: date)?.dayTypeID)
    }
}
