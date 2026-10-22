import XCTest
import SwiftData
@testable import Hours

/// Opening a store written by a build from before the app could sync.
///
/// This is the one schema change in the app's history that could lose somebody
/// a year of hours: CloudKit refuses a store carrying a unique constraint, so
/// dropping it was unavoidable, and dropping it changes the entity's version
/// hash. Whether or not anyone writes a migration, one happens. These tests are
/// the difference between believing it works and knowing.
@MainActor
final class MigrationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL.temporaryDirectory.appending(path: "hours-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    private var storeURL: URL { directory.appending(path: "Hours.store") }

    /// Writes a store in the old shape and closes it, exactly as a build from
    /// before the change would have left one on someone's phone.
    private func writeVersionOneStore(days: [(key: Int, note: String)], holidays: Int = 0) throws {
        let schema = Schema(versionedSchema: HoursSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        for day in days {
            let entry = HoursSchemaV1.DayEntry(dateKey: day.key)
            entry.note = day.note
            entry.startMinutes = 8 * 60
            entry.endMinutes = 16 * 60 + 30
            entry.isIncluded = true
            context.insert(entry)
        }
        for index in 0..<holidays {
            let record = HoursSchemaV1.HolidayRecord(identifier: UUID())
            record.name = "Holiday \(index)"
            record.month = 12
            record.day = 25
            context.insert(record)
        }
        try context.save()
    }

    /// Writes a store exactly as every build between sync and sites left one:
    /// the live `DayEntry` and `HolidayRecord` classes, and nothing else.
    ///
    /// Deliberately not `HoursSchemaV2`'s frozen copies. Those copies are only
    /// right if they hash the same as the classes that really wrote people's
    /// stores, and writing with the real classes is what proves it: a mistake
    /// in the frozen copy leaves this store matching no version, and the open
    /// below fails.
    private func writeVersionTwoStore(days: [(key: Int, note: String)], holidays: Int = 0) throws {
        let schema = Schema([DayEntry.self, HolidayRecord.self], version: Schema.Version(2, 0, 0))
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        for day in days {
            let entry = DayEntry(dateKey: day.key)
            entry.apply(
                DayRecord(
                    date: CalendarDate(key: day.key) ?? Fixture.date(2026, 1, 1),
                    shifts: [Shift(start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 30))],
                    note: day.note
                )
            )
            context.insert(entry)
        }
        for index in 0..<holidays {
            context.insert(HolidayRecord(rule: HolidayRule(
                name: "Holiday \(index)",
                recurrence: HolidayRecurrence(kind: .annual, month: 12, day: 25)
            )))
        }
        try context.save()
    }

    // MARK: - The migration itself

    func testAStoreWrittenBeforeSyncStillOpens() throws {
        try writeVersionOneStore(days: [(20_260_803, "Monday"), (20_260_804, "Tuesday")])

        let container = try HoursModelContainer.make(at: storeURL)
        let repository = WorkdayRepository(context: ModelContext(container))

        XCTAssertEqual(repository.allEntries().count, 2, "the migration must not lose days")
    }

    /// Not just the row count — the contents.
    func testEveryFieldSurvives() throws {
        try writeVersionOneStore(days: [(20_260_803, "cleared the backlog")])

        let container = try HoursModelContainer.make(at: storeURL)
        let repository = WorkdayRepository(context: ModelContext(container))
        let record = try XCTUnwrap(repository.record(on: Fixture.date(2026, 8, 3)))

        XCTAssertEqual(record.note, "cleared the backlog")
        XCTAssertEqual(record.start?.minutes, 8 * 60)
        XCTAssertEqual(record.end?.minutes, 16 * 60 + 30)
        XCTAssertTrue(record.isIncluded)
    }

    func testHolidaysSurviveToo() throws {
        try writeVersionOneStore(days: [], holidays: 3)

        let container = try HoursModelContainer.make(at: storeURL)
        let repository = WorkdayRepository(context: ModelContext(container))

        XCTAssertEqual(repository.holidayRules().count, 3)
    }

    /// The migration runs once; opening again is an ordinary launch.
    func testOpeningTwiceIsStable() throws {
        try writeVersionOneStore(days: [(20_260_803, "Monday")])

        let first = try HoursModelContainer.make(at: storeURL)
        XCTAssertEqual(WorkdayRepository(context: ModelContext(first)).allEntries().count, 1)

        let second = try HoursModelContainer.make(at: storeURL)
        XCTAssertEqual(WorkdayRepository(context: ModelContext(second)).allEntries().count, 1)
    }

    /// After the migration the constraint is gone, which is the entire point:
    /// with it still in place, a sync merge delivering a second row for the
    /// same day would fail the write rather than be reconciled.
    func testTheMigratedStoreAcceptsWhatSyncWouldDeliver() throws {
        try writeVersionOneStore(days: [(20_260_803, "from this phone")])

        let container = try HoursModelContainer.make(at: storeURL)
        let context = ModelContext(container)

        let arrival = DayEntry(dateKey: 20_260_803)
        arrival.note = "from the iPad"
        arrival.updatedAt = Date().addingTimeInterval(60)
        context.insert(arrival)
        XCTAssertNoThrow(try context.save(), "a duplicate must be storable, then reconciled")

        // And the repository resolves it on the next read, as it does for any
        // duplicate that sync produces.
        let repository = WorkdayRepository(context: context)
        XCTAssertEqual(repository.record(on: Fixture.date(2026, 8, 3))?.note, "from the iPad")
        XCTAssertEqual(repository.allEntries().count, 1)
    }

    // MARK: - Sites (V2 to V3)

    /// Adding sites must not cost anyone a day: a store from before sites
    /// opens as V3 with every day and holiday where it was, and the new
    /// entities are there, empty, ready to be written.
    func testV2StoreOpensAsV3WithDaysIntact() throws {
        try writeVersionTwoStore(days: [(20_260_803, "Monday"), (20_260_804, "Tuesday")], holidays: 2)

        let container = try HoursModelContainer.make(at: storeURL)
        let context = ModelContext(container)
        let repository = WorkdayRepository(context: context)

        XCTAssertEqual(repository.allEntries().count, 2, "the migration must not lose days")
        let record = try XCTUnwrap(repository.record(on: Fixture.date(2026, 8, 4)))
        XCTAssertEqual(record.note, "Tuesday")
        XCTAssertEqual(record.shifts.first?.start?.minutes, 7 * 60)
        XCTAssertEqual(record.shifts.first?.end?.minutes, 15 * 60 + 30)
        XCTAssertEqual(repository.holidayRules().count, 2)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CrewMemberEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteDayEntry>()), 0)

        let site = Site(name: "Hauptstraße 12")
        context.insert(SiteEntry(site: site))
        context.insert(CrewMemberEntry(member: CrewMember(siteID: site.id, name: "Ana")))
        context.insert(SiteDayEntry(day: SiteDay(siteID: site.id, date: Fixture.date(2026, 8, 3))))
        XCTAssertNoThrow(try context.save())

        // And it is an ordinary launch from then on.
        let second = try HoursModelContainer.make(at: storeURL)
        let reopened = ModelContext(second)
        XCTAssertEqual(WorkdayRepository(context: reopened).allEntries().count, 2)
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<SiteEntry>()).map(\.site), [site])
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<CrewMemberEntry>()), 1)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<SiteDayEntry>()), 1)
    }

    /// The oldest stores go the whole way, V1 through V2 to V3, in one open.
    func testAVersionOneStoreReachesVersionThree() throws {
        try writeVersionOneStore(days: [(20_260_803, "Monday")], holidays: 1)

        let container = try HoursModelContainer.make(at: storeURL)
        let context = ModelContext(container)

        XCTAssertEqual(WorkdayRepository(context: context).allEntries().count, 1)
        XCTAssertEqual(WorkdayRepository(context: context).holidayRules().count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteDayEntry>()), 0)
    }

    // MARK: - The site diary (V3 to V4)

    /// Writes a store as 1.0 left one: the five V3 entities. Written with
    /// V3's frozen copies, since the live site day has moved on; they were
    /// copied column for column from the classes 1.0 shipped.
    private func writeVersionThreeStore(siteDayKey: Int) throws -> UUID {
        let schema = Schema(versionedSchema: HoursSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let site = HoursSchemaV3.SiteEntry(siteID: siteID.uuidString)
        site.name = "Hauptstraße 12"
        context.insert(site)
        let day = HoursSchemaV3.SiteDayEntry(siteID: siteID.uuidString, dateKey: siteDayKey)
        day.startMinutes = 7 * 60
        day.endMinutes = 16 * 60
        day.note = "Concrete"
        context.insert(day)
        context.insert(HoursSchemaV3.DayEntry(dateKey: siteDayKey))
        try context.save()
        return siteID
    }

    /// A 1.0 store opens as V4: its site day intact and not rained off, and
    /// the diary, photo and signature entities there, empty, ready to write.
    func testAVersionThreeStoreOpensAsVersionFour() throws {
        let siteID = try writeVersionThreeStore(siteDayKey: 20_260_804)

        let container = try HoursModelContainer.make(at: storeURL)
        let context = ModelContext(container)
        let days = try context.fetch(FetchDescriptor<SiteDayEntry>())
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days.first?.siteDay.note, "Concrete")
        XCTAssertEqual(days.first?.siteDay.isBadWeatherStop, false)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteDiaryEntry>()), 0)

        context.insert(SiteDiaryEntry(diary: SiteDiary(siteID: siteID, date: Fixture.date(2026, 8, 4), workDone: "Rebar")))
        context.insert(SiteDiaryPhotoEntry(photo: DiaryPhoto(siteID: siteID, date: Fixture.date(2026, 8, 4), sortOrder: 0, jpegData: Data([1, 2, 3]))))
        XCTAssertNoThrow(try context.save())
    }

    /// The oldest stores go the whole way, V1 to V4, in one open.
    func testAVersionOneStoreReachesVersionFour() throws {
        try writeVersionOneStore(days: [(20_260_803, "Monday")], holidays: 1)
        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        XCTAssertEqual(WorkdayRepository(context: context).allEntries().count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteDiaryEntry>()), 0)
    }

    func testDiaryPhotoAndSignatureEntriesRoundTrip() {
        let siteID = UUID()
        let diary = SiteDiary(siteID: siteID, date: Fixture.date(2026, 8, 4), weather: .wind, temperatureCelsius: 3, problems: "Gusts")
        XCTAssertEqual(SiteDiaryEntry(diary: diary).diary, diary)
        let photo = DiaryPhoto(siteID: siteID, date: Fixture.date(2026, 8, 4), sortOrder: 1, jpegData: Data([9, 9]))
        XCTAssertEqual(SiteDiaryPhotoEntry(photo: photo).photo, photo)
        let signature = CrewSignature(
            siteID: siteID, memberID: CrewMember.youID, month: YearMonth(year: 2026, month: 8),
            signedOn: Fixture.date(2026, 8, 31), fingerprint: "v1:x",
            strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]], aspectRatio: 2.5
        )
        XCTAssertEqual(CrewSignatureEntry(signature: signature).signature, signature)
        let stopped = SiteDay(siteID: siteID, date: Fixture.date(2026, 8, 4), isBadWeatherStop: true)
        XCTAssertEqual(SiteDayEntry(day: stopped).siteDay, stopped)
    }

    /// Everything a site day holds comes back out of the store as it went in,
    /// including per-person exceptions and a job frozen on the day.
    func testSiteDayEntryRoundTripsSiteDay() throws {
        let you = Attendance(memberID: CrewMember.youID)
        let late = Attendance(
            memberID: UUID(),
            start: TimeOfDay(hour: 9, minute: 15),
            end: TimeOfDay(hour: 17, minute: 0),
            breakMinutes: 45
        )
        let day = SiteDay(
            siteID: UUID(),
            date: Fixture.date(2026, 10, 20),
            start: TimeOfDay(hour: 7, minute: 0),
            end: TimeOfDay(hour: 16, minute: 0),
            breakMinutes: 30,
            present: [you, late],
            note: "Concrete poured",
            jobID: UUID()
        )

        let container = HoursModelContainer.ephemeral()
        let context = ModelContext(container)
        context.insert(SiteDayEntry(day: day))
        try context.save()

        let stored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<SiteDayEntry>()).first)
        XCTAssertEqual(stored.siteDay, day)
        XCTAssertEqual(stored.dateKey, 20_261_020)
        XCTAssertEqual(stored.siteID, day.siteID.uuidString)
    }

    /// A day with nothing optional set stays that way: no times, nobody
    /// present, no job.
    func testAnEmptySiteDayRoundTrips() {
        let day = SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 21))
        let entry = SiteDayEntry(day: day)

        XCTAssertEqual(entry.siteDay, day)
        XCTAssertNil(entry.startMinutes)
        XCTAssertNil(entry.presentData)
        XCTAssertNil(entry.jobID)
    }

    /// `apply` changes the hours, never which site and date the row is for:
    /// moving a day is a delete and an insert, as it is for `DayEntry`.
    func testApplyingASiteDayKeepsTheRowsIdentity() {
        let original = SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 20), breakMinutes: 30)
        let entry = SiteDayEntry(day: original)

        var edited = original
        edited.breakMinutes = 45
        edited.note = "Rain from noon"
        entry.apply(edited)

        XCTAssertEqual(entry.siteDay, edited)

        let elsewhere = SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 22))
        entry.apply(elsewhere)
        XCTAssertEqual(entry.siteID, original.siteID.uuidString)
        XCTAssertEqual(entry.dateKey, 20_261_020)
    }

    func testSiteAndCrewEntriesRoundTrip() {
        let site = Site(name: "Bahnhof Nord", jobID: UUID(), isArchived: true, sortOrder: 3)
        XCTAssertEqual(SiteEntry(site: site).site, site)

        let member = CrewMember(siteID: site.id, name: "Marko", isHidden: true, sortOrder: 2)
        XCTAssertEqual(CrewMemberEntry(member: member).member, member)
    }

    /// Identifiers are stored as strings. One that is damaged (by a sync
    /// conflict, a hand-edited store) degrades the way the engine's lenient
    /// decoding does rather than crashing the app on launch.
    func testADamagedIdentifierFallsBackRatherThanCrashing() {
        let entry = SiteDayEntry(day: SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 20), jobID: UUID()))
        entry.siteID = "not a uuid"
        entry.jobID = "nor this"
        entry.presentData = Data("garbage".utf8)

        let day = entry.siteDay
        XCTAssertNil(day.jobID)
        XCTAssertTrue(day.present.isEmpty)

        let site = SiteEntry(site: Site(name: "Damaged", jobID: UUID()))
        site.jobID = "?"
        XCTAssertNil(site.site.jobID)
        XCTAssertEqual(site.site.name, "Damaged")
    }

    // MARK: - The plan itself

    func testThePlanGoesFromTheOldestVersionToTheCurrentOne() {
        XCTAssertEqual(HoursMigrationPlan.schemas.count, 4)
        XCTAssertEqual(HoursMigrationPlan.stages.count, 3)
        XCTAssertEqual(HoursSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HoursSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(HoursSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(HoursSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
    }

    /// The container is built from the newest schema, so a new model that is
    /// missing from it would be a crash the first time anything inserts one.
    func testTheContainerKnowsEveryModel() {
        let names = Set(HoursModelContainer.schema.entities.map(\.name))
        XCTAssertEqual(names, [
            "DayEntry", "HolidayRecord", "SiteEntry", "CrewMemberEntry", "SiteDayEntry",
            "SiteDiaryEntry", "SiteDiaryPhotoEntry", "CrewSignatureEntry"
        ])
    }

    /// A fresh install has no migrating to do and must not be slowed or broken
    /// by the plan being present.
    func testAFreshStoreOpensWithThePlanInPlace() throws {
        let container = try HoursModelContainer.make(at: storeURL)
        let repository = WorkdayRepository(context: ModelContext(container))

        XCTAssertTrue(repository.allEntries().isEmpty)
    }
}
