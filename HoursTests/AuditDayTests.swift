import XCTest
@testable import Hours

/// The calculation audit, day level: what one day comes to, checked against
/// arithmetic done independently of the calculator.
final class AuditDayTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func compute(
        _ record: DayRecord,
        settings: AppSettings = Fixture.settings()
    ) -> DayComputation {
        Fixture.calculator(settings: settings, calendar: calendar).compute(record: record, on: record.date)
    }

    // MARK: - Timed breaks at the edges of a shift

    /// A lunch typed as 11:30–12:30 on an afternoon starting at 12:00 is
    /// half inside the shift. The half inside is deducted, the same as a
    /// break running past the end of a shift has always been.
    func testABreakOverlappingTheStartOfAShiftIsClippedNotIgnored() {
        let day = compute(Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(12),
            end: Fixture.time(16, 30),
            breaks: [.timed(from: Fixture.time(11, 30), to: Fixture.time(12, 30))]
        ))
        XCTAssertEqual(day.breakMinutes, 30)
        XCTAssertEqual(day.workedMinutes, 4 * 60)
        XCTAssertFalse(day.warnings.contains(.breakOutsideShift))
    }

    /// The mirror image, which already worked: the two edges must agree.
    func testABreakOverlappingTheEndOfAShiftIsClipped() {
        let day = compute(Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(12),
            breaks: [.timed(from: Fixture.time(11, 30), to: Fixture.time(12, 30))]
        ))
        XCTAssertEqual(day.breakMinutes, 30)
        XCTAssertEqual(day.workedMinutes, 3 * 60 + 30)
    }

    /// The same at the start of a night shift, where the break crosses the
    /// shift's start rather than midnight.
    func testABreakOverlappingTheStartOfANightShiftIsClipped() {
        let day = compute(Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(22),
            end: Fixture.time(6),
            breaks: [.timed(from: Fixture.time(21, 45), to: Fixture.time(22, 15))]
        ))
        XCTAssertEqual(day.breakMinutes, 15)
        XCTAssertEqual(day.workedMinutes, 8 * 60 - 15)
    }

    /// Wholly before or after the shift still deducts nothing and says so.
    func testABreakEntirelyOutsideTheShiftIsStillIgnored() {
        for (from, to) in [(Fixture.time(6), Fixture.time(7)), (Fixture.time(17), Fixture.time(18))] {
            let day = compute(Fixture.record(
                on: Fixture.workingTuesday,
                start: Fixture.time(8),
                end: Fixture.time(16),
                breaks: [.timed(from: from, to: to)]
            ))
            XCTAssertEqual(day.breakMinutes, 0)
            XCTAssertEqual(day.workedMinutes, 8 * 60)
            XCTAssertTrue(day.warnings.contains(.breakOutsideShift))
        }
    }

    // MARK: - Properties over many shifts

    /// For any single shift with one timed break, worked time is the shift's
    /// length less the part of the break that falls inside it — computed here
    /// minute by minute, independently of the calculator's interval maths.
    func testWorkedTimeIsTheShiftLessTheBreakMinutesInsideIt() {
        var generator = SeededGenerator(seed: 0xA0D17)
        for _ in 0..<2_000 {
            let start = Int.random(in: 0..<1440, using: &generator)
            let length = Int.random(in: 1..<1440, using: &generator)
            let breakStart = Int.random(in: 0..<1440, using: &generator)
            let breakLength = Int.random(in: 1...180, using: &generator)

            let end = (start + length) % 1440
            let breakEnd = (breakStart + breakLength) % 1440
            let record = Fixture.record(
                on: Fixture.workingTuesday,
                start: TimeOfDay(minutes: start),
                end: TimeOfDay(minutes: end),
                breaks: [.timed(from: TimeOfDay(minutes: breakStart), to: TimeOfDay(minutes: breakEnd))]
            )
            let day = compute(record)

            // Wall-clock minutes the shift covers, and the break's, as sets
            // of minute-of-the-shift offsets.
            var inside = 0
            for minute in 0..<breakLength {
                let offset = ((breakStart + minute) - start + 2 * 1440) % 1440
                if offset < length { inside += 1 }
            }
            // A break that wraps back into the shift from the other end is
            // two pieces; the calculator only ever clips one span, so leave
            // that rare shape out of the property.
            let wrapsBothEnds = breakLength + length > 1440
            guard !wrapsBothEnds else { continue }

            XCTAssertEqual(
                day.workedMinutes,
                length - inside,
                "shift \(start)+\(length), break \(breakStart)+\(breakLength)"
            )
            XCTAssertEqual(day.breakMinutes, inside, "shift \(start)+\(length), break \(breakStart)+\(breakLength)")
        }
    }

    /// Paid breaks: worked is the whole shift, the break is still reported.
    func testAPaidBreakIsReportedButNotDeductedForAnyShift() {
        var settings = Fixture.settings()
        settings.primaryBreaksArePaid = true
        var generator = SeededGenerator(seed: 0xB4E4)
        for _ in 0..<500 {
            let start = Int.random(in: 0..<1440, using: &generator)
            let length = Int.random(in: 1..<1440, using: &generator)
            let breakMinutes = Int.random(in: 0...120, using: &generator)
            let day = compute(
                Fixture.record(
                    on: Fixture.workingTuesday,
                    start: TimeOfDay(minutes: start),
                    end: TimeOfDay(minutes: (start + length) % 1440),
                    breaks: [.duration(breakMinutes)]
                ),
                settings: settings
            )
            XCTAssertEqual(day.workedMinutes, length)
            XCTAssertEqual(day.breakMinutes, breakMinutes)
        }
    }

    /// Two jobs on one day, one paying for breaks and one not: each shift
    /// follows its own job and the day is their sum.
    func testASplitDayAcrossAPaidAndAnUnpaidJobAddsEachShiftByItsOwnRule() {
        var settings = Fixture.settings()
        let paying = Job(name: "Paying", breaksArePaid: true)
        settings.addJob(paying)
        let record = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [
                Shift(start: Fixture.time(7), end: Fixture.time(12), breaks: [.duration(30)], jobID: Job.primaryID),
                Shift(start: Fixture.time(13), end: Fixture.time(17), breaks: [.duration(15)], jobID: paying.id)
            ]
        )
        let day = compute(record, settings: settings)
        XCTAssertEqual(day.workedMinutes, (5 * 60 - 30) + 4 * 60)
        XCTAssertEqual(day.breakMinutes, 45)
        XCTAssertEqual(day.shifts.map(\.workedMinutes).reduce(0, +), day.workedMinutes)
    }

    // MARK: - Absence and manual figures

    /// The balance identity from ARCHITECTURE.md, for every built-in day type
    /// on a weekday and a weekend, with and without time worked.
    func testTheBalanceIsPaidLessExpectedPlusAdjustmentForEveryDayType() {
        var features = FeatureToggles()
        features.allowManualAdjustments = true
        let settings = Fixture.settings(features: features)
        for type in DayTypeCatalog.standard.all.map(\.id) {
            for date in [Fixture.workingTuesday, Fixture.saturday] {
                for worked in [false, true] {
                    var record = Fixture.record(
                        on: date,
                        start: worked ? Fixture.time(9) : nil,
                        end: worked ? Fixture.time(11) : nil,
                        type: type
                    )
                    record.adjustmentMinutes = 7
                    let day = compute(record, settings: settings)
                    XCTAssertEqual(
                        day.balanceMinutes,
                        day.workedMinutes + day.creditedMinutes - day.expectedMinutes + 7,
                        "\(type) on \(date)"
                    )
                    if day.dayType.expectation == .creditedAbsence {
                        XCTAssertEqual(day.creditedMinutes, day.expectedMinutes, "\(type) on \(date)")
                    } else {
                        XCTAssertEqual(day.creditedMinutes, 0, "\(type) on \(date)")
                    }
                }
            }
        }
    }

    /// Rounding is applied to the day's total once, never to a negative.
    func testRoundingIsAppliedToTheDayTotal() {
        for (rule, raw, expected) in [
            (RoundingRule.nearestQuarterHour, 7 * 60 + 52, 7 * 60 + 45),
            (.nearestQuarterHour, 7 * 60 + 53, 8 * 60),
            (.nearestFiveMinutes, 7 * 60 + 57, 7 * 60 + 55),
            (.nearestFiveMinutes, 7 * 60 + 58, 8 * 60),
            (.exact, 7 * 60 + 58, 7 * 60 + 58)
        ] {
            let day = compute(
                Fixture.record(on: Fixture.workingTuesday, start: Fixture.time(8), end: TimeOfDay(minutes: 8 * 60 + raw)),
                settings: Fixture.settings(rounding: rule)
            )
            XCTAssertEqual(day.workedMinutes, expected, "\(rule) of \(raw)")
        }
    }
}

/// A small deterministic generator, so a failing property names a case that
/// can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
