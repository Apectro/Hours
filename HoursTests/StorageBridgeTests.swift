import XCTest
@testable import Hours

/// The seam between a value the engine understands and a row SwiftData stores.
///
/// These live together for one reason: `DayEntry` is a `@Model`, and
/// `ExportFileFactory` reaches for `UniformTypeIdentifiers`. Both are
/// Apple-only, and a single test touching either was enough to keep its whole
/// file off the Linux job — which is the cheap one, and the one that runs on
/// every push. Five tests were holding three files hostage: every table, CSV
/// and workbook assertion, every shift calculation, and every adjustment rule
/// could only be checked on a macOS runner billed at ten times the rate.
///
/// So the Apple-only handful moved here, and the engine tests went back to the
/// runner that can afford them.
final class StorageBridgeTests: XCTestCase {
    private func adjusted(_ date: CalendarDate, minutes: Int, reason: AdjustmentReason) -> DayRecord {
        DayRecord(
            date: date,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)],
            adjustmentMinutes: minutes,
            adjustmentReason: reason
        )
    }

    // MARK: - Reading rows written by older builds

    func testAStoredEntryFromBeforeShiftsIsMigratedOnRead() {
        let entry = DayEntry(dateKey: Fixture.workingTuesday.key)
        // Exactly what an older build would have written.
        entry.startMinutes = 480
        entry.endMinutes = 990
        entry.breaksData = try? JSONEncoder().encode([BreakSpan.duration(30)])

        XCTAssertEqual(entry.resolvedShifts.count, 1)
        XCTAssertEqual(entry.record.start, Fixture.time(8))
        XCTAssertEqual(entry.record.end, Fixture.time(16, 30))
        XCTAssertEqual(entry.record.breaks.first?.explicitMinutes, 30)
    }

    func testWritingAnEntryClearsTheLegacyColumns() {
        let entry = DayEntry(dateKey: Fixture.workingTuesday.key)
        entry.startMinutes = 480
        entry.endMinutes = 990

        entry.apply(DayRecord(date: Fixture.workingTuesday, start: Fixture.time(9), end: Fixture.time(17)))

        XCTAssertNil(entry.startMinutes)
        XCTAssertNil(entry.endMinutes)
        XCTAssertNil(entry.breaksData)
        XCTAssertNotNil(entry.shiftsData)
        XCTAssertEqual(entry.record.start, Fixture.time(9))
    }

    // MARK: - Round trips

    func testASplitShiftEntryRoundTripsThroughStorage() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12)),
                Shift(start: Fixture.time(13), end: Fixture.time(17))
            ]
        )
        let entry = DayEntry(dateKey: record.date.key)
        entry.apply(record)

        XCTAssertEqual(entry.record, record)
    }

    func testTheAdjustmentReasonSurvivesStorageAndBackup() throws {
        let record = adjusted(Fixture.workingTuesday, minutes: -600, reason: .timeOffInLieu)

        let entry = DayEntry(dateKey: record.date.key)
        entry.apply(record)
        XCTAssertEqual(entry.record.adjustmentReason, .timeOffInLieu)

        let restored = try JSONDecoder().decode(DayRecord.self, from: try JSONEncoder().encode(record))
        XCTAssertEqual(restored.adjustmentReason, .timeOffInLieu)
    }

    // MARK: - Naming the file that leaves the app

    func testFilenamesAreSafe() {
        XCTAssertEqual(ExportFileFactory.sanitise("Hours 2026-08"), "Hours 2026-08")
        XCTAssertEqual(ExportFileFactory.sanitise("a/b:c"), "a-b-c")
        XCTAssertEqual(ExportFileFactory.sanitise("   "), "Hours")
    }
}
