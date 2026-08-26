import XCTest
import SwiftData
@testable import Hours

/// What happens when two devices recorded the same day.
///
/// Only sync can produce this. The schema used to forbid it outright, but
/// CloudKit refuses a store with a unique constraint, so the rule moved into
/// the repository and these are the tests that hold it there.
@MainActor
final class DuplicateReconciliationTests: XCTestCase {
    private let date = Fixture.workingTuesday

    private func makeRepository() -> (WorkdayRepository, ModelContext) {
        let container = HoursModelContainer.ephemeral()
        let context = ModelContext(container)
        return (WorkdayRepository(context: context), context)
    }

    /// Inserts straight into the context, bypassing `save`, which is exactly
    /// what a sync merge does.
    @discardableResult
    private func insertRaw(
        into context: ModelContext,
        note: String,
        updatedAt: Date,
        createdAt: Date? = nil
    ) -> DayEntry {
        let entry = DayEntry(dateKey: date.key)
        entry.note = note
        entry.createdAt = createdAt ?? updatedAt
        entry.updatedAt = updatedAt
        context.insert(entry)
        try? context.save()
        return entry
    }

    private func count(_ context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
    }

    func testTheDayEditedMostRecentlyWins() {
        let (repository, context) = makeRepository()
        insertRaw(into: context, note: "phone", updatedAt: Date(timeIntervalSince1970: 100))
        insertRaw(into: context, note: "iPad", updatedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(repository.record(on: date)?.note, "iPad")
        XCTAssertEqual(count(context), 1, "the losing row is removed, not merely hidden")
    }

    func testTheOrderTheyArrivedInDoesNotDecideIt() {
        let (repository, context) = makeRepository()
        insertRaw(into: context, note: "iPad", updatedAt: Date(timeIntervalSince1970: 200))
        insertRaw(into: context, note: "phone", updatedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(repository.record(on: date)?.note, "iPad")
        XCTAssertEqual(count(context), 1)
    }

    /// Two edits within the same second are possible; creation breaks it.
    func testASharedUpdateTimeFallsBackToWhichWasCreatedLast() {
        let (repository, context) = makeRepository()
        let sameInstant = Date(timeIntervalSince1970: 500)
        insertRaw(into: context, note: "older", updatedAt: sameInstant, createdAt: Date(timeIntervalSince1970: 1))
        insertRaw(into: context, note: "newer", updatedAt: sameInstant, createdAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(repository.record(on: date)?.note, "newer")
        XCTAssertEqual(count(context), 1)
    }

    /// The dangerous case, and the reason nothing is deleted here.
    ///
    /// If two rows are indistinguishable and each device broke the tie its own
    /// way, both would delete what the other kept, both deletions would sync,
    /// and the day would be gone. A surviving duplicate is untidy; a deleted
    /// day is data loss.
    func testRowsNothingCanTellApartAreBothKept() {
        let (repository, context) = makeRepository()
        let sameInstant = Date(timeIntervalSince1970: 500)
        insertRaw(into: context, note: "one", updatedAt: sameInstant, createdAt: sameInstant)
        insertRaw(into: context, note: "other", updatedAt: sameInstant, createdAt: sameInstant)

        XCTAssertEqual(repository.reconcileDuplicates(), 0, "a tie is not a licence to delete")
        XCTAssertEqual(count(context), 2)
        XCTAssertNotNil(repository.record(on: date), "the day still reads as recorded")
    }

    /// And it resolves itself: an edit stamps one of them, which then wins
    /// outright on every device.
    func testEditingATiedDayResolvesIt() {
        let (repository, context) = makeRepository()
        let sameInstant = Date(timeIntervalSince1970: 500)
        insertRaw(into: context, note: "one", updatedAt: sameInstant, createdAt: sameInstant)
        insertRaw(into: context, note: "other", updatedAt: sameInstant, createdAt: sameInstant)

        repository.save(DayRecord(date: date, note: "typed just now"))

        // Read first, then count: the edit stamps one row, and the collapse
        // happens on the next read of the day rather than on the write.
        XCTAssertEqual(repository.record(on: date)?.note, "typed just now")
        XCTAssertEqual(count(context), 1, "the row the edit did not touch is plainly older now, and goes")
    }

    /// A tie among the newest does not protect a row that is plainly older —
    /// every device agrees that one loses, so deleting it is safe.
    func testAnOlderRowStillGoesWhenTheNewestTwoTie() {
        let (repository, context) = makeRepository()
        let sameInstant = Date(timeIntervalSince1970: 500)
        insertRaw(into: context, note: "stale", updatedAt: Date(timeIntervalSince1970: 100), createdAt: Date(timeIntervalSince1970: 100))
        insertRaw(into: context, note: "one", updatedAt: sameInstant, createdAt: sameInstant)
        insertRaw(into: context, note: "other", updatedAt: sameInstant, createdAt: sameInstant)

        XCTAssertEqual(repository.reconcileDuplicates(), 1)
        XCTAssertEqual(count(context), 2)
    }

    func testReadingARangeCollapsesDuplicatesToo() {
        let (repository, context) = makeRepository()
        insertRaw(into: context, note: "phone", updatedAt: Date(timeIntervalSince1970: 100))
        insertRaw(into: context, note: "iPad", updatedAt: Date(timeIntervalSince1970: 200))

        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
        let records = repository.records(in: range)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[date.key]?.note, "iPad")
    }

    func testReconcilingReportsHowManyItRemoved() {
        let (repository, context) = makeRepository()
        insertRaw(into: context, note: "a", updatedAt: Date(timeIntervalSince1970: 100))
        insertRaw(into: context, note: "b", updatedAt: Date(timeIntervalSince1970: 200))
        insertRaw(into: context, note: "c", updatedAt: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(repository.reconcileDuplicates(), 2)
        XCTAssertEqual(count(context), 1)
        XCTAssertEqual(repository.record(on: date)?.note, "c")
    }

    /// The overwhelmingly common case, and the one that must stay cheap.
    func testAStoreWithNoDuplicatesIsLeftAlone() {
        let (repository, context) = makeRepository()
        repository.save(DayRecord(date: date, note: "only one"))
        repository.save(DayRecord(date: Fixture.date(2026, 8, 5), note: "and another day"))

        XCTAssertEqual(repository.reconcileDuplicates(), 0)
        XCTAssertEqual(count(context), 2)
        XCTAssertEqual(repository.record(on: date)?.note, "only one")
    }

    /// Saving over a duplicated day must leave one row, not edit one and leave
    /// the other behind to win the next merge.
    func testSavingOverADuplicatedDayLeavesOneRow() {
        let (repository, context) = makeRepository()
        insertRaw(into: context, note: "phone", updatedAt: Date(timeIntervalSince1970: 100))
        insertRaw(into: context, note: "iPad", updatedAt: Date(timeIntervalSince1970: 200))

        repository.save(DayRecord(date: date, note: "typed just now"))

        XCTAssertEqual(count(context), 1)
        XCTAssertEqual(repository.record(on: date)?.note, "typed just now")
    }

    // MARK: - Holidays

    func testDuplicateHolidaysCollapseToOne() {
        let (repository, context) = makeRepository()
        let rule = HolidayRule(name: "Christmas", recurrence: .annual(month: 12, day: 25))

        context.insert(HolidayRecord(rule: rule))
        context.insert(HolidayRecord(rule: rule))
        try? context.save()

        XCTAssertEqual(repository.holidayRules().count, 1)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<HolidayRecord>())) ?? 0, 1)
    }
}
