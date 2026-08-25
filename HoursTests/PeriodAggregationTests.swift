import XCTest
@testable import Hours

/// Totals, counts and the running balance.
final class PeriodAggregationTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// August 2026: 31 days, 21 of them Monday to Friday.
    private var august: CalendarDateRange {
        YearMonth(year: 2026, month: 8).range(in: calendar)
    }

    private func fullMonthOfEightHourDays() -> [Int: DayRecord] {
        var records: [Int: DayRecord] = [:]
        for date in august.days(in: calendar) {
            let weekday = date.weekday(in: calendar)
            guard weekday != 1 && weekday != 7 else { continue }
            records[date.key] = DayRecord(
                date: date,
                start: Fixture.time(8),
                end: Fixture.time(16, 30),
                breaks: [.duration(30)]
            )
        }
        return records
    }

    func testAMonthOfExactDaysBalancesToZero() {
        let engine = Fixture.engine(calendar: calendar)
        let summary = engine.summary(
            in: august,
            records: fullMonthOfEightHourDays(),
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.scheduledWorkingDays, 21)
        XCTAssertEqual(summary.daysWorked, 21)
        XCTAssertEqual(summary.workedMinutes, 21 * 480)
        XCTAssertEqual(summary.expectedMinutes, 21 * 480)
        XCTAssertEqual(summary.balanceMinutes, 0)
        XCTAssertEqual(summary.daysOff, 10)
        XCTAssertEqual(summary.averageWorkedMinutesPerWorkedDay, 480)
        XCTAssertEqual(summary.breakMinutes, 21 * 30)
    }

    func testOvertimeAndShortfallAreReportedSeparatelyAsWellAsNetted() {
        var records = fullMonthOfEightHourDays()
        records[Fixture.date(2026, 8, 3).key] = DayRecord(
            date: Fixture.date(2026, 8, 3),
            start: Fixture.time(8),
            end: Fixture.time(18, 30),
            breaks: [.duration(30)]
        )
        records[Fixture.date(2026, 8, 4).key] = DayRecord(
            date: Fixture.date(2026, 8, 4),
            start: Fixture.time(8),
            end: Fixture.time(15, 30),
            breaks: [.duration(30)]
        )

        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.overtimeMinutes, 120)
        XCTAssertEqual(summary.deficitMinutes, 60)
        XCTAssertEqual(summary.balanceMinutes, 60)
    }

    func testExcludedDaysContributeNothingAtAll() {
        var records = fullMonthOfEightHourDays()
        var excluded = records[Fixture.date(2026, 8, 3).key]
        excluded?.isIncluded = false
        records[Fixture.date(2026, 8, 3).key] = excluded

        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.daysWorked, 20)
        XCTAssertEqual(summary.workedMinutes, 20 * 480)
        XCTAssertEqual(summary.scheduledWorkingDays, 20)
        XCTAssertEqual(summary.balanceMinutes, 0, "the excluded day's expected hours are not owed either")
    }

    func testDaysStillToComeDoNotCountAsAShortfall() {
        // Nothing recorded all month, viewed on the 10th.
        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: [:],
            holidays: [],
            countingThrough: Fixture.date(2026, 8, 10)
        )

        // Monday 3rd to Monday 10th is six working days.
        XCTAssertEqual(summary.scheduledWorkingDays, 6)
        XCTAssertEqual(summary.balanceMinutes, -6 * 480)
    }

    func testAFutureDayThatWasDeliberatelyRecordedStillCounts() {
        let plannedLeave = Fixture.date(2026, 8, 20)
        let records = [plannedLeave.key: DayRecord(date: plannedLeave, dayTypeID: .vacation)]

        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 8, 10)
        )

        XCTAssertEqual(summary.count(of: .vacation), 1)
        XCTAssertEqual(summary.paidAbsenceDays, 1)
        XCTAssertEqual(summary.creditedMinutes, 480)
    }

    func testPaidAbsenceIsReportedApartFromHoursActuallyWorked() {
        var records = fullMonthOfEightHourDays()
        for day in [3, 4, 5] {
            let date = Fixture.date(2026, 8, day)
            records[date.key] = DayRecord(date: date, dayTypeID: .vacation)
        }

        let summary = Fixture.engine(calendar: calendar).summary(
            in: august,
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.workedMinutes, 18 * 480)
        XCTAssertEqual(summary.creditedMinutes, 3 * 480)
        XCTAssertEqual(summary.paidMinutes, 21 * 480)
        XCTAssertEqual(summary.expectedMinutes, 21 * 480)
        XCTAssertEqual(summary.balanceMinutes, 0)
        XCTAssertEqual(summary.count(of: .vacation), 3)
        XCTAssertEqual(summary.daysWorked, 18)
    }

    // MARK: - Running balance

    func testTheRunningBalanceAccumulatesAcrossMonths() {
        let january = Fixture.date(2026, 1, 5)
        let february = Fixture.date(2026, 2, 5)

        let engine = Fixture.engine(calendar: calendar)
        let records: [Int: DayRecord] = [
            january.key: DayRecord(date: january, start: Fixture.time(8), end: Fixture.time(20, 30), breaks: [.duration(30)]),
            february.key: DayRecord(date: february, start: Fixture.time(8), end: Fixture.time(15, 30), breaks: [.duration(30)])
        ]

        let range = CalendarDateRange(start: Fixture.date(2026, 1, 1), end: Fixture.date(2026, 2, 28))
        let days = engine.days(in: range, records: records, holidays: [])
            .filter { $0.hasEntry }

        let balance = BalanceLedger.cumulative(over: days, openingMinutes: 0, startDate: nil)
        XCTAssertEqual(balance, 240 - 60, "+4 h in January, −1 h in February")
    }

    func testAnOpeningBalanceIsCarriedIn() {
        let day = Fixture.date(2026, 1, 5)
        let records = [day.key: DayRecord(date: day, start: Fixture.time(8), end: Fixture.time(17), breaks: [])]
        let days = Fixture.engine(calendar: calendar)
            .days(in: CalendarDateRange(single: day), records: records, holidays: [])

        let balance = BalanceLedger.cumulative(over: days, openingMinutes: 180, startDate: nil)
        XCTAssertEqual(balance, 180 + 60)
    }

    func testDaysBeforeTheBalanceStartDateAreIgnored() {
        let early = Fixture.date(2026, 1, 5)
        let later = Fixture.date(2026, 2, 5)
        let records: [Int: DayRecord] = [
            early.key: DayRecord(date: early, start: Fixture.time(8), end: Fixture.time(17)),
            later.key: DayRecord(date: later, start: Fixture.time(8), end: Fixture.time(17))
        ]
        let range = CalendarDateRange(start: early, end: later)
        let days = Fixture.engine(calendar: calendar)
            .days(in: range, records: records, holidays: [])
            .filter { $0.hasEntry }

        let balance = BalanceLedger.cumulative(
            over: days,
            openingMinutes: 0,
            startDate: Fixture.date(2026, 2, 1)
        )
        XCTAssertEqual(balance, 60, "only February's hour counts")
    }

    func testTheMonthlySeriesIsOrderedAndCumulative() {
        let january = Fixture.date(2026, 1, 5)
        let february = Fixture.date(2026, 2, 5)
        let records: [Int: DayRecord] = [
            january.key: DayRecord(date: january, start: Fixture.time(8), end: Fixture.time(17)),
            february.key: DayRecord(date: february, start: Fixture.time(8), end: Fixture.time(17))
        ]
        let range = CalendarDateRange(start: Fixture.date(2026, 1, 1), end: Fixture.date(2026, 2, 28))
        let days = Fixture.engine(calendar: calendar)
            .days(in: range, records: records, holidays: [])
            .filter { $0.hasEntry }

        let series = BalanceLedger.monthlySeries(over: days, openingMinutes: 0, startDate: nil)

        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].month, YearMonth(year: 2026, month: 1))
        XCTAssertEqual(series[0].cumulativeMinutes, 60)
        XCTAssertEqual(series[1].cumulativeMinutes, 120)
    }

    // MARK: - A year

    func testAYearOfPerfectDaysBalancesToZero() {
        let year = CalendarDateRange.year(2026, in: calendar)
        var records: [Int: DayRecord] = [:]
        for date in year.days(in: calendar) {
            let weekday = date.weekday(in: calendar)
            guard weekday != 1 && weekday != 7 else { continue }
            records[date.key] = DayRecord(
                date: date,
                start: Fixture.time(8),
                end: Fixture.time(16, 30),
                breaks: [.duration(30)]
            )
        }

        let summary = Fixture.engine(calendar: calendar).summary(
            in: year,
            records: records,
            holidays: [],
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(summary.balanceMinutes, 0)
        XCTAssertEqual(summary.workedMinutes, summary.expectedMinutes)
        XCTAssertEqual(summary.scheduledWorkingDays, summary.daysWorked)
    }
}
