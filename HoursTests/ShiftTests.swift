import XCTest
@testable import Hours

/// Days made of more than one block of work.
final class ShiftTests: XCTestCase {
    private let calendar = Fixture.calendar()

    // MARK: - Summing

    func testTwoBlocksAddUpToOneFullDay() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12)),
                Shift(start: Fixture.time(13), end: Fixture.time(17))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
        XCTAssertEqual(result.shifts.count, 2)
        XCTAssertTrue(result.isSplitShift)
    }

    func testTheGapBetweenBlocksIsNotWorkedAndIsNotABreak() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12)),
                Shift(start: Fixture.time(17), end: Fixture.time(21))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480, "the five hours off in the middle are simply not work")
        XCTAssertEqual(result.breakMinutes, 0, "and they are not a break either")
    }

    func testTheDayReportsTheFirstStartAndTheLastEnd() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12)),
                Shift(start: Fixture.time(13), end: Fixture.time(17, 30))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.start, Fixture.time(8))
        XCTAssertEqual(result.end, Fixture.time(17, 30))
    }

    // MARK: - Breaks belong to their own shift

    func testABreakIsClippedToItsOwnShiftNotTheWholeDay() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                // The break sits in the gap between the blocks, so it belongs to
                // neither and must not be deducted from the first.
                Shift(start: Fixture.time(8), end: Fixture.time(12),
                      breaks: [.timed(from: Fixture.time(12, 30), to: Fixture.time(13))]),
                Shift(start: Fixture.time(13), end: Fixture.time(17))
            ]
        )
        var warnings: [DayWarning] = []
        let definition = DayTypeCatalog.standard.definition(for: .work)
        let result = Fixture.calculator().shiftMinutes(
            record: record,
            on: Fixture.workingTuesday,
            definition: definition,
            warnings: &warnings
        )

        XCTAssertEqual(result.breakMinutes, 0)
        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertTrue(warnings.contains(.breakOutsideShift))
    }

    func testEachShiftDeductsItsOwnBreak() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12), breaks: [.duration(15)]),
                Shift(start: Fixture.time(13), end: Fixture.time(17), breaks: [.duration(30)])
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.breakMinutes, 45)
        XCTAssertEqual(result.workedMinutes, 480 - 45)
    }

    func testOneOvernightBlockAmongSeveral() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(9), end: Fixture.time(12)),
                Shift(start: Fixture.time(22), end: Fixture.time(2))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 180 + 240)
        XCTAssertTrue(result.crossesMidnight)
        XCTAssertEqual(result.shifts.count, 2)
        XCTAssertFalse(result.shifts[0].crossesMidnight)
        XCTAssertTrue(result.shifts[1].crossesMidnight)
    }

    func testAnIncompleteBlockIsWarnedAboutOnlyOnce() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8)),
                Shift(start: Fixture.time(13))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertEqual(result.warnings.filter { $0 == .missingEndTime }.count, 1)
    }

    // MARK: - The single-shift accessors

    func testSettingATimeOnADayWithNoShiftsCreatesOne() {
        var record = DayRecord(date: Fixture.workingTuesday)
        XCTAssertTrue(record.shifts.isEmpty)

        record.start = Fixture.time(8)
        XCTAssertEqual(record.shifts.count, 1)
        XCTAssertEqual(record.shifts[0].start, Fixture.time(8))
    }

    func testClearingATimeOnAnEmptyDayDoesNotConjureAShift() {
        var record = DayRecord(date: Fixture.workingTuesday)
        record.start = nil
        record.end = nil
        record.breaks = []

        XCTAssertTrue(record.shifts.isEmpty)
        XCTAssertTrue(record.isBlank)
    }

    func testTheAccessorsAddressTheFirstShift() {
        var record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12)),
                Shift(start: Fixture.time(13), end: Fixture.time(17))
            ]
        )
        XCTAssertEqual(record.start, Fixture.time(8))
        XCTAssertEqual(record.end, Fixture.time(12), "the first shift's end, not the day's")

        record.end = Fixture.time(11)
        XCTAssertEqual(record.shifts[0].end, Fixture.time(11))
        XCTAssertEqual(record.shifts[1].end, Fixture.time(17), "the second block is untouched")
    }

    func testBlanknessLooksAtEveryShift() {
        XCTAssertTrue(DayRecord(date: Fixture.workingTuesday, shifts: [Shift()]).isBlank)
        XCTAssertFalse(
            DayRecord(date: Fixture.workingTuesday, shifts: [Shift(), Shift(start: Fixture.time(8))]).isBlank
        )
    }

    // MARK: - Reading what earlier versions wrote

    func testABackupWrittenBeforeShiftsExistedStillRestores() throws {
        let legacy = """
        {
          "date": 20260804,
          "start": 480,
          "end": 990,
          "breaks": [{"id":"3E7B1E4E-0000-4000-8000-000000000001","explicitMinutes":30}],
          "adjustmentMinutes": 0,
          "note": "from an older version",
          "location": "",
          "tags": [],
          "isIncluded": true
        }
        """
        let record = try JSONDecoder().decode(DayRecord.self, from: Data(legacy.utf8))

        XCTAssertEqual(record.shifts.count, 1)
        XCTAssertEqual(record.start, Fixture.time(8))
        XCTAssertEqual(record.end, Fixture.time(16, 30))
        XCTAssertEqual(record.breaks.first?.explicitMinutes, 30)
        XCTAssertEqual(record.note, "from an older version")
    }

    func testASplitShiftDayRoundTrips() throws {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(8), end: Fixture.time(12), breaks: [.duration(15)]),
                Shift(start: Fixture.time(13), end: Fixture.time(17))
            ],
            note: "split"
        )
        let restored = try JSONDecoder().decode(DayRecord.self, from: try JSONEncoder().encode(record))

        XCTAssertEqual(restored, record)
        XCTAssertEqual(restored.shifts.count, 2)
    }

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
}
