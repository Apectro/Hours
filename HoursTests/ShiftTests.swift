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

    // MARK: - The order blocks are read in

    /// A split shift entered afternoon-first still reads morning-first.
    ///
    /// The day's start and end come off the first and last period, and those
    /// are the Start and End columns of an export. In entry order this day
    /// exported "13:00" as its start and "12:00" as its end — a reversed range
    /// on a timesheet. Adding a block appends it, so entering two out of order
    /// takes no effort at all.
    func testBlocksAreReadInTimeOrderNotEntryOrder() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(13), end: Fixture.time(17)),
                Shift(start: Fixture.time(8), end: Fixture.time(12))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.start, Fixture.time(8), "the day starts when the first block starts")
        XCTAssertEqual(result.end, Fixture.time(17), "the day ends when the last block ends")
        XCTAssertEqual(result.shifts.map(\.start), [Fixture.time(8), Fixture.time(13)])
        XCTAssertEqual(result.workedMinutes, 480, "reordering changes nothing about the total")
    }

    /// Three blocks, thoroughly shuffled.
    func testAnyNumberOfBlocksComesBackInOrder() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(16), end: Fixture.time(18)),
                Shift(start: Fixture.time(8), end: Fixture.time(10)),
                Shift(start: Fixture.time(12), end: Fixture.time(14))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(
            result.shifts.map(\.start),
            [Fixture.time(8), Fixture.time(12), Fixture.time(16)]
        )
        XCTAssertEqual(result.start, Fixture.time(8))
        XCTAssertEqual(result.end, Fixture.time(18))
    }

    /// A day running past midnight keeps the order it was entered in.
    ///
    /// There is no unambiguous wall-clock order once a day crosses midnight:
    /// 00:30 sorts before 22:00 and happens after it. Entry order is at least
    /// what the person typed, which beats an ordering that is confidently
    /// wrong — and the hours, which is what actually gets paid, are the same
    /// either way.
    func testAnOvernightDayIsLeftInTheOrderItWasEnteredIn() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(22), end: Fixture.time(2))]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertTrue(result.crossesMidnight)
        XCTAssertEqual(result.start, Fixture.time(22))
        XCTAssertEqual(result.end, Fixture.time(2))
        XCTAssertEqual(result.workedMinutes, 240)
    }
}
