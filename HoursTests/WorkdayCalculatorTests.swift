import XCTest
@testable import Hours

/// The arithmetic of a single day. If anything in the app is going to be
/// right, it is this.
final class WorkdayCalculatorTests: XCTestCase {

    // MARK: - The ordinary case

    func testEightHourDayIsExactlyOnTarget() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.breakMinutes, 30)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
        XCTAssertEqual(result.overtimeMinutes, 0)
        XCTAssertEqual(result.dayType.id, .work)
        XCTAssertFalse(result.crossesMidnight)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testLongDayProducesOvertime() {
        let record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(18),
            breaks: [.duration(30)]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 570)
        XCTAssertEqual(result.balanceMinutes, 90)
        XCTAssertEqual(result.overtimeMinutes, 90)
        XCTAssertEqual(result.deficitMinutes, 0)
    }

    func testShortDayProducesANegativeBalance() {
        let record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(15),
            breaks: [.duration(30)]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 390)
        XCTAssertEqual(result.balanceMinutes, -90)
        XCTAssertEqual(result.overtimeMinutes, 0)
        XCTAssertEqual(result.deficitMinutes, 90)
    }

    func testNoBreakIsNotAnError() {
        let record = Fixture.record(on: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.breakMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    // MARK: - Breaks

    func testSeveralBreaksAreAddedTogether() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(8),
            end: Fixture.time(18),
            breaks: [.duration(30), .duration(15)]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.breakMinutes, 45)
        XCTAssertEqual(result.workedMinutes, 555)
    }

    func testOverlappingBreaksAreNotDeductedTwice() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(8),
            end: Fixture.time(18),
            breaks: [
                .timed(from: Fixture.time(12), to: Fixture.time(13)),
                .timed(from: Fixture.time(12, 30), to: Fixture.time(13, 30))
            ]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.breakMinutes, 90, "12:00–13:30 once, not 120 minutes")
        XCTAssertEqual(result.workedMinutes, 510)
        XCTAssertTrue(result.warnings.contains(.overlappingBreaksMerged))
    }

    func testBreakOutsideTheShiftIsIgnoredAndFlagged() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(8),
            end: Fixture.time(16),
            breaks: [.timed(from: Fixture.time(18), to: Fixture.time(18, 30))]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.breakMinutes, 0)
        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertTrue(result.warnings.contains(.breakOutsideShift))
    }

    func testBreakLongerThanTheShiftClampsToZeroRatherThanGoingNegative() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(8),
            end: Fixture.time(9),
            breaks: [.duration(120)]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertTrue(result.warnings.contains(.breakLongerThanShift))
    }

    func testNegativeBreakDurationsAreImpossible() {
        let span = BreakSpan.duration(-45)
        XCTAssertEqual(span.explicitMinutes, 0)
    }

    // MARK: - Overnight

    func testOvernightShiftIsMeasuredAcrossMidnight() {
        let record = Fixture.record(on: Fixture.workingMonday, start: Fixture.time(22), end: Fixture.time(6))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertTrue(result.crossesMidnight)
    }

    func testBreakAfterMidnightBelongsToTheShiftThatStartedYesterday() {
        let record = Fixture.record(
            on: Fixture.workingMonday,
            start: Fixture.time(22),
            end: Fixture.time(6),
            breaks: [.timed(from: Fixture.time(2), to: Fixture.time(2, 30))]
        )
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.breakMinutes, 30)
        XCTAssertEqual(result.workedMinutes, 450)
    }

    func testIdenticalStartAndEndCountsAsNothingRatherThanAFullDay() {
        let record = Fixture.record(on: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(8))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertTrue(result.warnings.contains(.zeroLengthShift))
    }

    // MARK: - Incomplete entry

    func testAMissingEndTimeIsFlaggedAndCountsAsNothing() {
        let record = Fixture.record(on: Fixture.workingMonday, start: Fixture.time(8))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertTrue(result.warnings.contains(.missingEndTime))
        XCTAssertFalse(result.warnings.contains(.missingStartTime))
    }

    func testADayWithNoEntryAtAllProducesNoWarnings() {
        let result = Fixture.calculator().compute(record: nil, on: Fixture.workingMonday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, -480)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertFalse(result.hasEntry)
    }

    // MARK: - Day types

    func testWeekendExpectsNothing() {
        let result = Fixture.calculator().compute(record: nil, on: Fixture.saturday)

        XCTAssertEqual(result.dayType.id, .weekend)
        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testWorkingASaturdayIsAllOvertime() {
        let record = Fixture.record(on: Fixture.saturday, start: Fixture.time(9), end: Fixture.time(13))
        let result = Fixture.calculator().compute(record: record, on: Fixture.saturday)

        XCTAssertEqual(result.workedMinutes, 240)
        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 240)
    }

    func testVacationCreditsTheContractedHoursAndLeavesTheBalanceAlone() {
        let record = Fixture.record(on: Fixture.workingTuesday, type: .vacation)
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 0)
        XCTAssertEqual(result.creditedMinutes, 480)
        XCTAssertEqual(result.paidMinutes, 480)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testVacationOnASaturdayChangesNothing() {
        let record = Fixture.record(on: Fixture.saturday, type: .vacation)
        let result = Fixture.calculator().compute(record: record, on: Fixture.saturday)

        XCTAssertEqual(result.creditedMinutes, 0)
        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testSickLeaveBehavesLikeOtherPaidAbsence() {
        let record = Fixture.record(on: Fixture.workingTuesday, type: .sick)
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.creditedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    // MARK: - Holidays

    func testAHolidayOnAWorkingDayIsPaidAbsence() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))
        let result = Fixture.calculator().compute(record: nil, on: Fixture.workingTuesday, holiday: holiday)

        XCTAssertEqual(result.dayType.id, .holiday)
        XCTAssertEqual(result.holidayName, "Assumption")
        XCTAssertEqual(result.creditedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testAHolidayFallingOnAWeekendChangesNothing() {
        let holiday = HolidayRule(name: "Weekend holiday", recurrence: .annual(month: 8, day: 8))
        let result = Fixture.calculator().compute(record: nil, on: Fixture.saturday, holiday: holiday)

        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.creditedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testWorkingOnAHolidayIsEntirelyOvertime() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))
        let record = Fixture.record(on: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(10))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday, holiday: holiday)

        XCTAssertEqual(result.workedMinutes, 120)
        XCTAssertEqual(result.creditedMinutes, 480)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 120)
    }

    func testAHolidayWorkedAsNormalKeepsItsContractedHours() {
        let holiday = HolidayRule(
            name: "Company day",
            recurrence: .annual(month: 8, day: 4),
            countsAsWorkingDay: true
        )
        let record = Fixture.record(on: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16))
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday, holiday: holiday)

        XCTAssertEqual(result.dayType.id, .work)
        XCTAssertEqual(result.creditedMinutes, 0)
        XCTAssertEqual(result.expectedMinutes, 480)
        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testAnExplicitDayTypeBeatsAHolidayRule() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))
        let record = Fixture.record(on: Fixture.workingTuesday, type: .vacation)
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday, holiday: holiday)

        XCTAssertEqual(result.dayType.id, .vacation)
        XCTAssertEqual(result.creditedMinutes, 480, "still one day of credit, not two")
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    // MARK: - Overrides and corrections

    func testAPerDayExpectedOverrideReplacesTheSchedule() {
        var record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(12)
        )
        record.expectedOverrideMinutes = 240
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.expectedMinutes, 240)
        XCTAssertEqual(result.workedMinutes, 240)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testAnAdjustmentMovesTheBalanceWithoutTouchingTheHours() {
        var record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)]
        )
        record.adjustmentMinutes = -60
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480)
        XCTAssertEqual(result.balanceMinutes, -60)
    }

    func testAManualWorkedFigureOverridesTheTimes() {
        var record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)]
        )
        record.manualWorkedMinutes = 300
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 300)
        XCTAssertEqual(result.balanceMinutes, -180)
    }

    func testAManualBalanceOverridesTheCalculation() {
        var record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(18)
        )
        record.manualBalanceMinutes = 15
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.balanceMinutes, 15)
    }

    func testRoundingToTheNearestQuarterHour() {
        let settings = Fixture.settings(rounding: .nearestQuarterHour)
        let record = Fixture.record(on: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16, 7))
        let result = Fixture.calculator(settings: settings).compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 480, "487 minutes rounds down to 8 hours")
    }

    // MARK: - Feature toggles

    func testSwitchingOffBreakTrackingStopsBreaksBeingDeducted() {
        var features = FeatureToggles()
        features.trackBreaks = false
        let settings = Fixture.settings(features: features)
        let record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(18),
            breaks: [.duration(30)]
        )
        let result = Fixture.calculator(settings: settings).compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 600)
        XCTAssertEqual(result.breakMinutes, 0)
    }

    func testSwitchingOffExpectedHoursRemovesTheBalanceEntirely() {
        var features = FeatureToggles()
        features.trackExpectedHours = false
        let settings = Fixture.settings(features: features)
        let record = Fixture.record(on: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(18))
        let result = Fixture.calculator(settings: settings).compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.workedMinutes, 600)
        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    func testSwitchingOffHolidayTrackingIgnoresHolidayRules() {
        var features = FeatureToggles()
        features.trackHolidays = false
        let settings = Fixture.settings(features: features)
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 4))
        let result = Fixture.calculator(settings: settings)
            .compute(record: nil, on: Fixture.workingTuesday, holiday: holiday)

        XCTAssertEqual(result.dayType.id, .work)
        XCTAssertNil(result.holidayName)
    }

    // MARK: - Exclusion

    func testAnExcludedDayIsFlagged() {
        var record = Fixture.record(
            on: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(18)
        )
        record.isIncluded = false
        let result = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)

        XCTAssertFalse(result.isIncluded)
        XCTAssertTrue(result.warnings.contains(.excludedFromTotals))
    }
}
