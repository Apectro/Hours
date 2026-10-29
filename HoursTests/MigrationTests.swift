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
    /// `DayEntry` and `HolidayRecord` as they stood from V2 to V7, and nothing
    /// else.
    ///
    /// Until V8 this wrote with the live classes, which had not changed since
    /// V2. V8 adds columns to the live `DayEntry`, so it now writes with V7's
    /// frozen copies, which are those same classes column for column, and not
    /// with `HoursSchemaV2`'s. A mistake in either frozen copy leaves this store
    /// matching no version, and the open below fails.
    private func writeVersionTwoStore(days: [(key: Int, note: String)], holidays: Int = 0) throws {
        let schema = Schema(
            [HoursSchemaV7.DayEntry.self, HoursSchemaV7.HolidayRecord.self],
            version: Schema.Version(2, 0, 0)
        )
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        for day in days {
            let entry = HoursSchemaV7.DayEntry(dateKey: day.key)
            entry.shiftsData = DayEntry.encodeShifts(
                [Shift(start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 30))]
            )
            entry.note = day.note
            entry.isIncluded = true
            context.insert(entry)
        }
        for index in 0..<holidays {
            let record = HoursSchemaV7.HolidayRecord(identifier: UUID())
            record.name = "Holiday \(index)"
            record.kindRawValue = HolidayRecurrence.Kind.annual.rawValue
            record.month = 12
            record.day = 25
            context.insert(record)
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

    // MARK: - Extra work (V4 to V5)

    /// Writes a store as 1.1 before extra work left one: the eight V4
    /// entities, with V4's frozen copies — a diary, a photo, a signature.
    private func writeVersionFourStore(siteDayKey: Int) throws -> UUID {
        let schema = Schema(versionedSchema: HoursSchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let site = HoursSchemaV4.SiteEntry(siteID: siteID.uuidString)
        site.name = "Trg Pravde Zagreb"
        context.insert(site)
        let day = HoursSchemaV4.SiteDayEntry(siteID: siteID.uuidString, dateKey: siteDayKey)
        day.startMinutes = 7 * 60
        day.endMinutes = 16 * 60
        day.isBadWeatherStop = true
        context.insert(day)
        let diary = HoursSchemaV4.SiteDiaryEntry(siteID: siteID.uuidString, dateKey: siteDayKey)
        diary.workDone = "Cable trays"
        context.insert(diary)
        let photo = HoursSchemaV4.SiteDiaryPhotoEntry(photoID: UUID().uuidString)
        photo.siteID = siteID.uuidString
        photo.dateKey = siteDayKey
        photo.jpegData = Data([1, 2, 3])
        context.insert(photo)
        context.insert(HoursSchemaV4.CrewSignatureEntry(siteID: siteID.uuidString, memberID: CrewMember.youID.uuidString, monthKey: siteDayKey / 100))
        context.insert(HoursSchemaV4.DayEntry(dateKey: siteDayKey))
        try context.save()
        return siteID
    }

    /// A store from before extra work opens as V5 with its diary intact and
    /// the extra-work entities there, empty, ready to write.
    func testAVersionFourStoreOpensAsVersionFive() throws {
        let siteID = try writeVersionFourStore(siteDayKey: 20_261_022)

        let container = try HoursModelContainer.make(at: storeURL)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteDayEntry>()).first?.isBadWeatherStop, true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteDiaryEntry>()).first?.workDone, "Cable trays")
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteDiaryPhotoEntry>()).first?.jpegData, Data([1, 2, 3]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CrewSignatureEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExtraWorkJobEntry>()), 0)

        let job = ExtraWorkJob(
            siteID: siteID, date: Fixture.date(2026, 10, 22), description: "Emergency lights",
            items: [ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces)]
        )
        context.insert(ExtraWorkJobEntry(job: job))
        context.insert(ExtraWorkPhotoEntry(photo: ExtraWorkPhoto(jobID: job.id, siteID: siteID, sortOrder: 0, jpegData: Data([4]))))
        context.insert(ExtraWorkReportEntry(record: ExtraWorkReportRecord(siteID: siteID, sentAt: Date(), jobIDs: [job.id])))
        context.insert(ExtraWorkItemEntry(item: ExtraWorkCatalogItem(name: "Emergency light", unit: .pieces)))
        XCTAssertNoThrow(try context.save())
    }

    /// The oldest stores go the whole way, V1 to V9, in one open.
    func testAVersionOneStoreReachesTheNewestVersion() throws {
        try writeVersionOneStore(days: [(20_260_803, "Monday")], holidays: 1)
        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        XCTAssertEqual(WorkdayRepository(context: context).allEntries().count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExtraWorkJobEntry>()), 0)

        // And takes a site day with a reason someone was away.
        let siteID = UUID()
        let day = SiteDay(siteID: siteID, date: Fixture.date(2026, 10, 23))
            .settingAbsence(.sick, for: UUID())
        context.insert(SiteDayEntry(day: day))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteDayEntry>()).first?.siteDay, day)

        // And the day as 1.2 keeps it, with the allowance and kilometres.
        let migrated = try XCTUnwrap(WorkdayRepository(context: context).record(on: Fixture.date(2026, 8, 3)))
        XCTAssertFalse(migrated.hasFieldAllowance)
        XCTAssertEqual(migrated.kilometres, 0)
        XCTAssertEqual(migrated.travelMinutes, 0)
        let allowance = SiteDay(siteID: siteID, date: Fixture.date(2026, 10, 24), present: [Attendance(memberID: CrewMember.youID)],
                                allowanceMemberIDs: [CrewMember.youID], kilometres: 40)
        context.insert(SiteDayEntry(day: allowance))
        XCTAssertNoThrow(try context.save())

        // And a site with its address (V9).
        let sites = SiteRepository(context: context)
        sites.upsert(Site(id: siteID, name: "Bau Süd", address: "Kaiserstraße 12\n10115 Berlin"))
        XCTAssertEqual(SiteRepository(context: context).site(id: siteID)?.address, "Kaiserstraße 12\n10115 Berlin")
    }

    // MARK: - Done (V5 to V6)

    /// Writes a store as 1.1 before a job could be in progress left one:
    /// V5's frozen copies, with two extra-work jobs — one sent, one still
    /// "invoiced", a step that no longer exists.
    private func writeVersionFiveStore() throws -> UUID {
        let schema = Schema(versionedSchema: HoursSchemaV5.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let site = HoursSchemaV5.SiteEntry(siteID: siteID.uuidString)
        site.name = "Trg Pravde Zagreb"
        context.insert(site)
        let diary = HoursSchemaV5.SiteDiaryEntry(siteID: siteID.uuidString, dateKey: 20_261_021)
        diary.workDone = "Cable trays"
        context.insert(diary)
        for (index, status) in ["sent", "invoiced"].enumerated() {
            let job = HoursSchemaV5.ExtraWorkJobEntry(jobID: UUID().uuidString)
            job.siteID = siteID.uuidString
            job.dateKey = 20_261_020 + index
            job.workDescription = "Job \(index)"
            job.statusRawValue = status
            job.sentAt = Date(timeIntervalSince1970: 1_792_000_000)
            context.insert(job)
        }
        let photo = HoursSchemaV5.ExtraWorkPhotoEntry(photoID: UUID().uuidString)
        photo.siteID = siteID.uuidString
        photo.jpegData = Data([7])
        context.insert(photo)
        context.insert(HoursSchemaV5.ExtraWorkReportEntry(reportID: UUID().uuidString))
        context.insert(HoursSchemaV5.ExtraWorkItemEntry(itemID: UUID().uuidString))
        try context.save()
        return siteID
    }

    /// Every job a V5 store holds was written as finished work, so it opens
    /// done — the stored default — with no date it was done, and an
    /// "invoiced" one reads as sent.
    func testAVersionFiveStoreOpensWithItsJobsDone() throws {
        let siteID = try writeVersionFiveStore()

        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        let jobs = ExtraWorkRepository(context: context).jobs(siteID: siteID)
        XCTAssertEqual(jobs.map(\.description), ["Job 0", "Job 1"])
        XCTAssertTrue(jobs.allSatisfy(\.isDone))
        XCTAssertTrue(jobs.allSatisfy { $0.doneAt == nil })
        XCTAssertEqual(jobs.map(\.status), [.sent, .sent])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteDiaryEntry>()).first?.workDone, "Cable trays")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ExtraWorkPhotoEntry>()).first?.jpegData, Data([7]))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExtraWorkReportEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExtraWorkItemEntry>()), 1)

        // And a new job, in progress, is written beside them.
        let fresh = ExtraWorkJob(siteID: siteID, date: Fixture.date(2026, 10, 23), description: "Under way")
        ExtraWorkRepository(context: context).storeJob(fresh)
        XCTAssertEqual(ExtraWorkRepository(context: context).job(id: fresh.id)?.isDone, false)
    }

    // MARK: - Absences (V6 to V7)

    /// Writes a store as 1.1 before crew absences left one: V6's frozen
    /// copies, with a site day and an extra-work job in progress.
    private func writeVersionSixStore() throws -> (site: UUID, member: UUID) {
        let schema = Schema(versionedSchema: HoursSchemaV6.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let memberID = UUID()
        let site = HoursSchemaV6.SiteEntry(siteID: siteID.uuidString)
        site.name = "Trg Pravde Zagreb"
        context.insert(site)
        let member = HoursSchemaV6.CrewMemberEntry(memberID: memberID.uuidString)
        member.siteID = siteID.uuidString
        member.name = "Ivo"
        context.insert(member)
        let day = HoursSchemaV6.SiteDayEntry(siteID: siteID.uuidString, dateKey: 20_261_022)
        day.startMinutes = 7 * 60
        day.endMinutes = 16 * 60
        day.presentData = SiteDayEntry.encodePresent([Attendance(memberID: CrewMember.youID)])
        context.insert(day)
        let job = HoursSchemaV6.ExtraWorkJobEntry(jobID: UUID().uuidString)
        job.siteID = siteID.uuidString
        job.dateKey = 20_261_022
        job.workDescription = "Cable trays"
        job.isDone = false
        context.insert(job)
        try context.save()
        return (siteID, memberID)
    }

    /// A V6 store opens with every site day as it was and no absences, and
    /// then takes a day with one.
    func testAVersionSixStoreOpensWithNoAbsences() throws {
        let (siteID, memberID) = try writeVersionSixStore()

        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        let sites = SiteRepository(context: context)
        let day = try XCTUnwrap(sites.siteDay(siteID: siteID, on: Fixture.date(2026, 10, 22)))
        XCTAssertEqual(day.present.map(\.memberID), [CrewMember.youID])
        XCTAssertEqual(day.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(day.absences, [])
        XCTAssertEqual(sites.crew(for: siteID, includeHidden: true).map(\.name), ["Ivo"])
        XCTAssertEqual(ExtraWorkRepository(context: context).jobs(siteID: siteID).first?.isDone, false)

        let sick = day.settingAbsence(.sick, for: memberID)
        try sites.save(sick)
        XCTAssertEqual(SiteRepository(context: context).siteDay(siteID: siteID, on: sick.date)?.absence(for: memberID), .sick)
    }

    // MARK: - Allowance and travel (V7 to V8)

    /// Writes a store as 1.1 left one: V7's frozen copies, with a day, a
    /// site and a site day with an absence.
    private func writeVersionSevenStore() throws -> (site: UUID, member: UUID) {
        let schema = Schema(versionedSchema: HoursSchemaV7.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let memberID = UUID()
        let site = HoursSchemaV7.SiteEntry(siteID: siteID.uuidString)
        site.name = "Trg Pravde Zagreb"
        context.insert(site)
        let member = HoursSchemaV7.CrewMemberEntry(memberID: memberID.uuidString)
        member.siteID = siteID.uuidString
        member.name = "Ivo"
        context.insert(member)
        let day = HoursSchemaV7.SiteDayEntry(siteID: siteID.uuidString, dateKey: 20_261_023)
        day.startMinutes = 7 * 60
        day.endMinutes = 15 * 60 + 30
        day.presentData = SiteDayEntry.encodePresent([Attendance(memberID: CrewMember.youID)])
        day.absenceData = SiteDayEntry.encodeAbsences([CrewAbsence(memberID: memberID, dayTypeID: .sick)])
        context.insert(day)
        let own = HoursSchemaV7.DayEntry(dateKey: 20_261_022)
        own.note = "Office"
        own.startMinutes = 8 * 60
        own.endMinutes = 16 * 60
        context.insert(own)
        try context.save()
        return (siteID, memberID)
    }

    /// A 1.1 store opens as V8 with everything where it was: no allowance,
    /// no kilometres, no travel, a site giving no allowance by default and
    /// with no location — and then takes all of them.
    func testAVersionSevenStoreOpensWithNoAllowanceAndTakesOne() throws {
        let (siteID, memberID) = try writeVersionSevenStore()

        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        let workdays = WorkdayRepository(context: context)
        let own = try XCTUnwrap(workdays.record(on: Fixture.date(2026, 10, 22)))
        XCTAssertEqual(own.note, "Office")
        XCTAssertEqual(own.start, TimeOfDay(hour: 8, minute: 0))
        XCTAssertFalse(own.hasFieldAllowance)
        XCTAssertEqual(own.kilometres, 0)
        XCTAssertEqual(own.travelMinutes, 0)

        let sites = SiteRepository(context: context)
        let site = try XCTUnwrap(sites.site(id: siteID))
        XCTAssertFalse(site.allowanceByDefault)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SiteEntry>()).first)
        XCTAssertNil(entry.latitude)
        XCTAssertNil(entry.longitude)
        XCTAssertEqual(entry.arrivalRadius, 150)
        XCTAssertFalse(entry.remindsOnArrival)

        let day = try XCTUnwrap(sites.siteDay(siteID: siteID, on: Fixture.date(2026, 10, 23)))
        XCTAssertEqual(day.absence(for: memberID), .sick)
        XCTAssertEqual(day.allowanceMemberIDs, [])
        XCTAssertEqual(day.kilometres, 0)

        // And it takes the new fields.
        try workdays.save(DayRecord(date: Fixture.date(2026, 10, 21), hasFieldAllowance: true, kilometres: 84, travelMinutes: 95))
        let written = try XCTUnwrap(WorkdayRepository(context: context).record(on: Fixture.date(2026, 10, 21)))
        XCTAssertTrue(written.hasFieldAllowance)
        XCTAssertEqual(written.kilometres, 84)
        XCTAssertEqual(written.travelMinutes, 95)

        var defaulted = site
        defaulted.allowanceByDefault = true
        sites.upsert(defaulted)
        XCTAssertEqual(SiteRepository(context: context).site(id: siteID)?.allowanceByDefault, true)

        let withAllowance = day.settingAllowance(true, for: CrewMember.youID)
        var driven = withAllowance
        driven.kilometres = 62
        try sites.save(driven)
        let stored = try XCTUnwrap(SiteRepository(context: context).siteDay(siteID: siteID, on: day.date))
        XCTAssertEqual(stored.allowanceMemberIDs, [CrewMember.youID])
        XCTAssertEqual(stored.kilometres, 62)
        // Your own day has the site's allowance and kilometres on its site shift.
        let yours = try XCTUnwrap(WorkdayRepository(context: context).record(on: day.date))
        XCTAssertEqual(yours.shifts.first?.fieldAllowance, true)
        XCTAssertEqual(yours.shifts.first?.kilometres, 62)
    }

    // MARK: - The site's address (V8 to V9)

    /// Writes a store as the first 1.2 builds left one: V8's frozen copies,
    /// with a site that has a place and an arrival reminder, and a site day.
    private func writeVersionEightStore() throws -> UUID {
        let schema = Schema(versionedSchema: HoursSchemaV8.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let siteID = UUID()
        let site = HoursSchemaV8.SiteEntry(siteID: siteID.uuidString)
        site.name = "Trg Pravde Zagreb"
        site.allowanceByDefault = true
        site.latitude = 45.8
        site.longitude = 15.97
        site.arrivalRadius = 300
        site.remindsOnArrival = true
        context.insert(site)
        let day = HoursSchemaV8.SiteDayEntry(siteID: siteID.uuidString, dateKey: 20_261_027)
        day.startMinutes = 7 * 60
        day.endMinutes = 15 * 60 + 30
        day.presentData = SiteDayEntry.encodePresent([Attendance(memberID: CrewMember.youID)])
        day.kilometres = 40
        context.insert(day)
        let own = HoursSchemaV8.DayEntry(dateKey: 20_261_026)
        own.note = "Office"
        own.kilometres = 12
        context.insert(own)
        try context.save()
        return siteID
    }

    /// A V8 store opens as V9 with every site, place and day as it was and
    /// no address, and then takes one.
    func testAVersionEightStoreOpensWithNoAddressAndTakesOne() throws {
        let siteID = try writeVersionEightStore()

        let context = ModelContext(try HoursModelContainer.make(at: storeURL))
        let sites = SiteRepository(context: context)
        let site = try XCTUnwrap(sites.site(id: siteID))
        XCTAssertEqual(site.name, "Trg Pravde Zagreb")
        XCTAssertTrue(site.allowanceByDefault)
        XCTAssertEqual(site.place, SitePlace(latitude: 45.8, longitude: 15.97))
        XCTAssertEqual(site.arrivalRadius, 300)
        XCTAssertTrue(site.remindsOnArrival)
        XCTAssertEqual(site.address, "")
        XCTAssertNil(try XCTUnwrap(context.fetch(FetchDescriptor<SiteEntry>()).first).address)

        let day = try XCTUnwrap(sites.siteDay(siteID: siteID, on: Fixture.date(2026, 10, 27)))
        XCTAssertEqual(day.start, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(day.kilometres, 40)
        XCTAssertEqual(WorkdayRepository(context: context).record(on: Fixture.date(2026, 10, 26))?.kilometres, 12)

        var addressed = site
        addressed.address = "Trg pravde 1\n10000 Zagreb"
        sites.upsert(addressed)
        let reread = try XCTUnwrap(SiteRepository(context: context).site(id: siteID))
        XCTAssertEqual(reread.address, "Trg pravde 1\n10000 Zagreb")
        XCTAssertEqual(reread.place, site.place, "the address leaves the place alone")
    }

    func testAnAddressIsStoredOnlyWhenSet() {
        let entry = SiteEntry(site: Site(name: "Bau Süd"))
        XCTAssertNil(entry.address)
        entry.apply(Site(name: "Bau Süd", address: "Kaiserstraße 12"))
        XCTAssertEqual(entry.address, "Kaiserstraße 12")
        XCTAssertEqual(entry.site.address, "Kaiserstraße 12")
        entry.apply(Site(name: "Bau Süd"))
        XCTAssertNil(entry.address)
        XCTAssertEqual(entry.site.address, "")
    }

    func testTheArrivalFieldsSurviveEditingTheSite() throws {
        let context = ModelContext(HoursModelContainer.ephemeral())
        let site = Site(name: "Bau Süd")
        let entry = SiteEntry(site: site)
        entry.latitude = 45.8
        entry.longitude = 15.97
        entry.arrivalRadius = 300
        entry.remindsOnArrival = true
        context.insert(entry)
        try context.save()

        // The site a screen edits is read from the entry, so it carries them.
        var renamed = entry.site
        XCTAssertEqual(renamed.place, SitePlace(latitude: 45.8, longitude: 15.97))
        XCTAssertEqual(renamed.arrivalRadius, 300)
        XCTAssertTrue(renamed.remindsOnArrival)
        renamed.name = "Bau Nord"
        entry.apply(renamed)
        XCTAssertEqual(entry.latitude, 45.8)
        XCTAssertEqual(entry.longitude, 15.97)
        XCTAssertEqual(entry.arrivalRadius, 300)
        XCTAssertTrue(entry.remindsOnArrival)

        // "Clear location" clears them.
        var cleared = entry.site
        cleared.place = nil
        cleared.remindsOnArrival = false
        entry.apply(cleared)
        XCTAssertNil(entry.latitude)
        XCTAssertNil(entry.longitude)
        XCTAssertFalse(entry.remindsOnArrival)
    }

    func testDayAndSiteDayEntriesKeepTheAllowance() {
        let record = DayRecord(date: Fixture.date(2026, 10, 23), hasFieldAllowance: true, kilometres: 12, travelMinutes: 30)
        let dayEntry = DayEntry(dateKey: record.date.key)
        dayEntry.apply(record)
        XCTAssertEqual(dayEntry.record, record)

        let siteDay = SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 23), present: [Attendance(memberID: CrewMember.youID)],
                              allowanceMemberIDs: [CrewMember.youID], kilometres: 40)
        let entry = SiteDayEntry(day: siteDay)
        XCTAssertEqual(entry.siteDay, siteDay)
        entry.apply(siteDay.settingAllowance(false, for: CrewMember.youID))
        XCTAssertNil(entry.allowanceData, "nobody stores nothing")
        XCTAssertEqual(SiteDayEntry.decodeAllowance(Data("damaged".utf8)), [])

        let site = Site(name: "Bau Süd", allowanceByDefault: true)
        XCTAssertEqual(SiteEntry(site: site).site, site)
    }

    /// A full bad-weather stop with the allowance: the site shift has no
    /// hours but is stored for what it carries.
    func testASiteShiftWithOnlyAnAllowanceIsStored() {
        let record = DayRecord(date: Fixture.date(2026, 10, 23), dayTypeID: .badWeather,
                               shifts: [Shift(id: UUID(), siteID: UUID(), fieldAllowance: true)])
        let entry = DayEntry(dateKey: record.date.key)
        entry.apply(record)
        XCTAssertNotNil(entry.shiftsData)
        XCTAssertEqual(entry.record.shifts.first?.fieldAllowance, true)
    }

    func testSiteDayEntryKeepsAbsences() {
        let day = SiteDay(siteID: UUID(), date: Fixture.date(2026, 10, 23), present: [Attendance(memberID: CrewMember.youID)])
            .settingAbsence(.vacation, for: UUID())
        let entry = SiteDayEntry(day: day)
        XCTAssertNotNil(entry.absenceData)
        XCTAssertEqual(entry.siteDay, day)
        entry.apply(day.settingAbsence(nil, for: day.absences[0].memberID))
        XCTAssertNil(entry.absenceData, "no absences store nothing")
        XCTAssertEqual(SiteDayEntry.decodeAbsences(Data("damaged".utf8)), [])
    }

    func testExtraWorkEntriesRoundTrip() {
        let siteID = UUID()
        var job = ExtraWorkJob(
            siteID: siteID, date: Fixture.date(2026, 10, 22), description: "Lamps",
            items: [ExtraWorkItem(name: "Cable", quantity: Decimal(string: "12.5")!, unit: .metres),
                    ExtraWorkItem(name: "Tape", quantity: 2, unit: .custom("Rolle"))],
            hours: [ExtraWorkHours(memberID: UUID(), name: "Ivan", minutes: 90)],
            clientSignature: ExtraWorkSignature(signerName: "Horvat", signedAt: Date(timeIntervalSince1970: 1_792_000_000),
                                                strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]),
            createdAt: Date(timeIntervalSince1970: 1_791_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_791_500_000)
        )
        job = job.markingSent(at: Date(timeIntervalSince1970: 1_792_000_000), reportID: UUID())
        XCTAssertEqual(ExtraWorkJobEntry(job: job).job, job)
        XCTAssertFalse(ExtraWorkJobEntry(job: job).isDone, "a job in progress is stored in progress, not with the default")
        let done = job.markingDone(at: Date(timeIntervalSince1970: 1_792_100_000))
        XCTAssertEqual(ExtraWorkJobEntry(job: done).job, done)

        let photo = ExtraWorkPhoto(jobID: job.id, siteID: siteID, sortOrder: 2, jpegData: Data([9]))
        XCTAssertEqual(ExtraWorkPhotoEntry(photo: photo).photo, photo)
        let record = ExtraWorkReportRecord(siteID: siteID, sentAt: Date(timeIntervalSince1970: 1_792_000_000), jobIDs: [job.id],
                                           clientSignature: job.clientSignature)
        XCTAssertEqual(ExtraWorkReportEntry(record: record).record, record)
        let item = ExtraWorkCatalogItem(name: "Cable", unit: .metres, useCount: 4, lastUsed: Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(ExtraWorkItemEntry(item: item).item, item)
    }

    /// What a CloudKit-mirrored store demands of every entity, checked on the
    /// schema the app opens: every attribute optional or with a default,
    /// nothing unique, every relationship optional with an inverse.
    func testEveryEntityIsOneCloudKitAccepts() {
        for entity in HoursModelContainer.schema.entities {
            for attribute in entity.attributes {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) needs a default or must be optional"
                )
                XCTAssertFalse(attribute.isUnique, "\(entity.name).\(attribute.name) must not be unique")
            }
            for relationship in entity.relationships {
                XCTAssertTrue(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional")
                XCTAssertNotNil(relationship.inverseKeyPath, "\(entity.name).\(relationship.name) needs an inverse")
            }
        }
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
        XCTAssertNil(entry.absenceData)
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
        XCTAssertEqual(HoursMigrationPlan.schemas.count, 9)
        XCTAssertEqual(HoursMigrationPlan.stages.count, 8)
        XCTAssertEqual(HoursSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HoursSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(HoursSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(HoursSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(HoursSchemaV5.versionIdentifier, Schema.Version(5, 0, 0))
        XCTAssertEqual(HoursSchemaV6.versionIdentifier, Schema.Version(6, 0, 0))
        XCTAssertEqual(HoursSchemaV7.versionIdentifier, Schema.Version(7, 0, 0))
        XCTAssertEqual(HoursSchemaV8.versionIdentifier, Schema.Version(8, 0, 0))
        XCTAssertEqual(HoursSchemaV9.versionIdentifier, Schema.Version(9, 0, 0))
    }

    /// The container is built from the newest schema, so a new model that is
    /// missing from it would be a crash the first time anything inserts one.
    func testTheContainerKnowsEveryModel() {
        let names = Set(HoursModelContainer.schema.entities.map(\.name))
        XCTAssertEqual(names, [
            "DayEntry", "HolidayRecord", "SiteEntry", "CrewMemberEntry", "SiteDayEntry",
            "SiteDiaryEntry", "SiteDiaryPhotoEntry", "CrewSignatureEntry",
            "ExtraWorkJobEntry", "ExtraWorkPhotoEntry", "ExtraWorkReportEntry", "ExtraWorkItemEntry"
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
