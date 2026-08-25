import XCTest
@testable import Hours

/// Dates, months, weeks and the grid. The dull arithmetic that everything
/// else stands on.
final class CalendarMathTests: XCTestCase {
    private let calendar = Fixture.calendar()

    func testDateKeysRoundTrip() {
        let date = Fixture.date(2026, 8, 4)
        XCTAssertEqual(date.key, 20260804)
        XCTAssertEqual(CalendarDate(key: 20260804), date)
        XCTAssertNil(CalendarDate(key: 20261304), "month 13 is not a date")
        XCTAssertNil(CalendarDate(key: 0))
    }

    func testDateKeysSortChronologically() {
        let dates = [
            Fixture.date(2026, 1, 2),
            Fixture.date(2025, 12, 31),
            Fixture.date(2026, 1, 1)
        ].sorted()
        XCTAssertEqual(dates.map(\.key), [20251231, 20260101, 20260102])
    }

    func testLeapYears() {
        XCTAssertEqual(YearMonth(year: 2024, month: 2).dayCount(in: calendar), 29)
        XCTAssertEqual(YearMonth(year: 2026, month: 2).dayCount(in: calendar), 28)
        XCTAssertEqual(YearMonth(year: 2000, month: 2).dayCount(in: calendar), 29)
        XCTAssertEqual(YearMonth(year: 1900, month: 2).dayCount(in: calendar), 28)
    }

    func testMonthLengths() {
        XCTAssertEqual(YearMonth(year: 2026, month: 8).dayCount(in: calendar), 31)
        XCTAssertEqual(YearMonth(year: 2026, month: 4).dayCount(in: calendar), 30)
    }

    func testMonthArithmeticCrossesYearBoundariesInBothDirections() {
        XCTAssertEqual(YearMonth(year: 2026, month: 12).adding(months: 1), YearMonth(year: 2027, month: 1))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).adding(months: -1), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).adding(months: -13), YearMonth(year: 2024, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 6).adding(months: 18), YearMonth(year: 2027, month: 12))
    }

    func testAddingDaysCrossesMonthAndYearEnds() {
        XCTAssertEqual(Fixture.date(2026, 8, 31).adding(days: 1, in: calendar), Fixture.date(2026, 9, 1))
        XCTAssertEqual(Fixture.date(2026, 1, 1).adding(days: -1, in: calendar), Fixture.date(2025, 12, 31))
        XCTAssertEqual(Fixture.date(2024, 2, 28).adding(days: 1, in: calendar), Fixture.date(2024, 2, 29))
        XCTAssertEqual(Fixture.date(2026, 2, 28).adding(days: 1, in: calendar), Fixture.date(2026, 3, 1))
    }

    func testAddingADayAcrossAClockChangeStillLandsOnTheNextDate() {
        XCTAssertEqual(
            Fixture.springForward.adding(days: -1, in: calendar),
            Fixture.date(2026, 3, 28)
        )
        XCTAssertEqual(
            Fixture.springForward.adding(days: 1, in: calendar),
            Fixture.date(2026, 3, 30)
        )
        XCTAssertEqual(
            Fixture.fallBack.adding(days: 1, in: calendar),
            Fixture.date(2026, 10, 26)
        )
    }

    func testWeekRangeRespectsTheFirstWeekday() {
        let mondayFirst = Fixture.calendar(firstWeekday: 2)
        let week = CalendarDateRange.week(containing: Fixture.workingTuesday, in: mondayFirst)
        XCTAssertEqual(week.start, Fixture.date(2026, 8, 3))
        XCTAssertEqual(week.end, Fixture.date(2026, 8, 9))

        let sundayFirst = Fixture.calendar(firstWeekday: 1)
        let otherWeek = CalendarDateRange.week(containing: Fixture.workingTuesday, in: sundayFirst)
        XCTAssertEqual(otherWeek.start, Fixture.date(2026, 8, 2))
        XCTAssertEqual(otherWeek.end, Fixture.date(2026, 8, 8))
    }

    func testAReversedRangeIsCorrectedRatherThanTrapped() {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 31), end: Fixture.date(2026, 8, 1))
        XCTAssertEqual(range.start, Fixture.date(2026, 8, 1))
        XCTAssertEqual(range.end, Fixture.date(2026, 8, 31))
    }

    func testRangeEnumerationIsInclusiveAtBothEnds() {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
        let days = range.days(in: calendar)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.first, Fixture.date(2026, 8, 1))
        XCTAssertEqual(days.last, Fixture.date(2026, 8, 31))
    }

    func testAYearRangeCoversALeapDay() {
        let days = CalendarDateRange.year(2024, in: calendar).days(in: calendar)
        XCTAssertEqual(days.count, 366)
        XCTAssertTrue(days.contains(Fixture.date(2024, 2, 29)))
    }

    // MARK: - Month grid

    func testAugust2026NeedsSixRowsStartingOnTheMondayBefore() {
        let layout = MonthLayout.make(
            month: YearMonth(year: 2026, month: 8),
            calendar: calendar,
            includesWeekends: true
        )
        XCTAssertEqual(layout.columnCount, 7)
        XCTAssertEqual(layout.rowCount, 6)
        XCTAssertEqual(layout.days.count, 42)
        XCTAssertEqual(layout.days.first, Fixture.date(2026, 7, 27))
        XCTAssertFalse(layout.isInMonth(Fixture.date(2026, 7, 27)))
        XCTAssertTrue(layout.isInMonth(Fixture.date(2026, 8, 1)))
    }

    func testHidingWeekendsLeavesFiveColumns() {
        let layout = MonthLayout.make(
            month: YearMonth(year: 2026, month: 8),
            calendar: calendar,
            includesWeekends: false
        )
        XCTAssertEqual(layout.columnCount, 5)
        XCTAssertEqual(layout.days.count % 5, 0)
        XCTAssertFalse(layout.days.contains { $0.weekday(in: calendar) == 1 || $0.weekday(in: calendar) == 7 })
    }

    func testAWeekLayoutDimsNothing() {
        let layout = MonthLayout.week(
            containing: Fixture.date(2026, 8, 31),
            calendar: calendar,
            includesWeekends: true
        )
        XCTAssertEqual(layout.days.count, 7)
        XCTAssertTrue(layout.isInMonth(Fixture.date(2026, 9, 1)), "a week spanning two months has no outside")
    }

    func testTheGridCoversEveryVisibleCell() {
        let layout = MonthLayout.make(
            month: YearMonth(year: 2026, month: 2),
            calendar: calendar,
            includesWeekends: true
        )
        let covered = layout.coveredRange
        XCTAssertEqual(covered.start, layout.days.first)
        XCTAssertEqual(covered.end, layout.days.last)
        for day in layout.days {
            XCTAssertTrue(covered.contains(day))
        }
    }

    // MARK: - Times

    func testTimeOfDayIsClampedToARealTime() {
        XCTAssertEqual(TimeOfDay(minutes: -30).minutes, 0)
        XCTAssertEqual(TimeOfDay(minutes: 5000).minutes, 1439)
        XCTAssertEqual(TimeOfDay(hour: 16, minute: 30).minutes, 990)
    }

    func testTimeRounding() {
        XCTAssertEqual(TimeOfDay(hour: 8, minute: 7).rounded(toNearest: 15).minutes, TimeOfDay(hour: 8, minute: 0).minutes)
        XCTAssertEqual(TimeOfDay(hour: 8, minute: 8).rounded(toNearest: 15).minutes, TimeOfDay(hour: 8, minute: 15).minutes)
    }

    // MARK: - Schedule

    func testWeeklyTargetIsTheSumUnlessOverridden() {
        var schedule = WorkSchedule()
        XCTAssertEqual(schedule.weeklyTargetMinutes, 5 * 480)
        XCTAssertEqual(schedule.workingDaysPerWeek, 5)

        schedule.weeklyTargetOverrideMinutes = 1900
        XCTAssertEqual(schedule.weeklyTargetMinutes, 1900)
        XCTAssertEqual(schedule.summedWeeklyMinutes, 5 * 480, "the per-day figures are untouched")
    }

    func testScheduleIndexesWeekdaysFromSunday() {
        var schedule = WorkSchedule(minutesByWeekday: [0, 0, 0, 0, 0, 0, 0])
        schedule.setContractedMinutes(360, forWeekday: 7)
        XCTAssertEqual(schedule.contractedMinutes(forWeekday: 7), 360)
        XCTAssertTrue(schedule.isWorkingWeekday(7))
        XCTAssertFalse(schedule.isWorkingWeekday(2))
    }

    func testScheduleValuesAreClamped() {
        let schedule = WorkSchedule(minutesByWeekday: [-100, 5000, 480, 480, 480, 480, 0])
        XCTAssertEqual(schedule.contractedMinutes(forWeekday: 1), 0)
        XCTAssertEqual(schedule.contractedMinutes(forWeekday: 2), 1440)
    }

    func testASaturdayWorkingScheduleMakesSaturdayAWorkingDay() {
        var schedule = WorkSchedule()
        schedule.setContractedMinutes(300, forWeekday: 7)
        let settings = Fixture.settings(schedule: schedule)
        let result = Fixture.calculator(settings: settings).compute(record: nil, on: Fixture.saturday)

        XCTAssertEqual(result.dayType.id, .work)
        XCTAssertEqual(result.expectedMinutes, 300)
    }
}
