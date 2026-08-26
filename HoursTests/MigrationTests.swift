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

    // MARK: - The plan itself

    func testThePlanGoesFromTheOldestVersionToTheCurrentOne() {
        XCTAssertEqual(HoursMigrationPlan.schemas.count, 2)
        XCTAssertEqual(HoursMigrationPlan.stages.count, 1)
        XCTAssertEqual(HoursSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(HoursSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
    }

    /// A fresh install has no migrating to do and must not be slowed or broken
    /// by the plan being present.
    func testAFreshStoreOpensWithThePlanInPlace() throws {
        let container = try HoursModelContainer.make(at: storeURL)
        let repository = WorkdayRepository(context: ModelContext(container))

        XCTAssertTrue(repository.allEntries().isEmpty)
    }
}
