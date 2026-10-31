import XCTest
@testable import Hours

/// The Today calendar's eighth column: each row of the month, its whole
/// week's hours (worked plus credited), Monday to Sunday even where the
/// row runs into the month before or after.
final class CalendarWeekTotalsTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// October 2026 starts on a Thursday and ends on a Saturday: five rows,
    /// 28 September to 1 November.
    private func october(weekends: Bool = true) -> MonthLayout {
        MonthLayout.make(month: YearMonth(year: 2026, month: 10), calendar: calendar, includesWeekends: weekends)
    }

    private func worked(_ date: CalendarDate, until hour: Int = 16, minute: Int = 30) -> DayRecord {
        DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(hour, minute), breaks: [.duration(30)])
    }

    private func days(
        _ records: [DayRecord],
        layout: MonthLayout
    ) -> [DayComputation] {
        var byKey: [Int: DayRecord] = [:]
        for record in records { byKey[record.date.key] = record }
        return Fixture.engine(calendar: calendar).days(
            in: CalendarWeekTotals.span(of: layout, calendar: calendar),
            records: byKey,
            holidays: []
        )
    }

    // MARK: - The rows and their weeks

    func testTheRowsAreTheLayoutsDaysAWeekToARow() {
        let rows = CalendarWeekTotals.rows(of: october())

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first?.first, Fixture.date(2026, 9, 28))
        XCTAssertEqual(rows.last?.last, Fixture.date(2026, 11, 1))
        XCTAssertTrue(rows.allSatisfy { $0.count == 7 })
    }

    func testEachRowsWeekIsMondayToSunday() {
        let weeks = CalendarWeekTotals.weeks(of: october(), calendar: calendar)

        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks[0], CalendarDateRange(start: Fixture.date(2026, 9, 28), end: Fixture.date(2026, 10, 4)))
        XCTAssertEqual(weeks[4], CalendarDateRange(start: Fixture.date(2026, 10, 26), end: Fixture.date(2026, 11, 1)))
    }

    func testWithoutWeekendsARowsWeekStillRunsToSunday() {
        let layout = october(weekends: false)
        let weeks = CalendarWeekTotals.weeks(of: layout, calendar: calendar)

        XCTAssertEqual(CalendarWeekTotals.rows(of: layout).first?.count, 5)
        XCTAssertEqual(weeks.last?.end, Fixture.date(2026, 11, 1))
        XCTAssertEqual(
            CalendarWeekTotals.span(of: layout, calendar: calendar),
            CalendarDateRange(start: Fixture.date(2026, 9, 28), end: Fixture.date(2026, 11, 1)),
            "the span covers the hidden weekend of the last row"
        )
    }

    func testAWeekLayoutIsOneRow() {
        let layout = MonthLayout.week(containing: Fixture.date(2026, 10, 30), calendar: calendar, includesWeekends: true)

        XCTAssertEqual(CalendarWeekTotals.weeks(of: layout, calendar: calendar), [
            CalendarDateRange(start: Fixture.date(2026, 10, 26), end: Fixture.date(2026, 11, 1))
        ])
    }

    // MARK: - The totals

    func testARowCountsTheDaysOfTheNeighbouringMonths() {
        let layout = october()
        let records = [
            worked(Fixture.date(2026, 9, 28)),
            worked(Fixture.date(2026, 10, 1)),
            worked(Fixture.date(2026, 10, 30)),
            worked(Fixture.date(2026, 11, 1), until: 12, minute: 30)
        ]

        let totals = CalendarWeekTotals.minutes(
            of: layout,
            days: days(records, layout: layout),
            calendar: calendar,
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(totals, [960, 0, 0, 0, 480 + 240])
    }

    func testCreditedAbsenceCountsAsWellAsWork() {
        let layout = october()
        let records = [
            worked(Fixture.date(2026, 10, 12), until: 17, minute: 30),
            DayRecord(date: Fixture.date(2026, 10, 13), dayTypeID: .vacation),
            DayRecord(date: Fixture.date(2026, 10, 14), dayTypeID: .sick)
        ]

        let totals = CalendarWeekTotals.minutes(
            of: layout,
            days: days(records, layout: layout),
            calendar: calendar,
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(totals[2], 540 + 480 + 480)
    }

    func testAHiddenWeekendStillCounts() {
        let layout = october(weekends: false)
        let records = [worked(Fixture.date(2026, 10, 17)), worked(Fixture.date(2026, 10, 16))]

        let totals = CalendarWeekTotals.minutes(
            of: layout,
            days: days(records, layout: layout),
            calendar: calendar,
            countingThrough: Fixture.date(2026, 12, 31)
        )

        XCTAssertEqual(totals[2], 960, "Saturday is not on the grid, but it is in the week")
    }

    func testDaysStillToComeCountOnlyWhatIsWritten() {
        let layout = october()
        let records = [
            worked(Fixture.date(2026, 10, 26)),
            DayRecord(date: Fixture.date(2026, 10, 29), dayTypeID: .vacation)
        ]

        let totals = CalendarWeekTotals.minutes(
            of: layout,
            days: days(records, layout: layout),
            calendar: calendar,
            countingThrough: Fixture.date(2026, 10, 27)
        )

        XCTAssertEqual(totals[4], 480 + 480, "booked leave counts; the empty days to come add nothing")
    }

    func testTheTotalIsThePeriodSummarysPaidHours() {
        let layout = october()
        let records = [
            worked(Fixture.date(2026, 10, 5), until: 18),
            DayRecord(date: Fixture.date(2026, 10, 6), dayTypeID: .vacation),
            worked(Fixture.date(2026, 10, 10))
        ]
        let computed = days(records, layout: layout)
        let week = CalendarWeekTotals.weeks(of: layout, calendar: calendar)[1]
        let today = Fixture.date(2026, 10, 8)

        let summary = PeriodAggregator.summarize(computed.filter { week.contains($0.date) }, range: week, countingThrough: today)
        let totals = CalendarWeekTotals.minutes(of: layout, days: computed, calendar: calendar, countingThrough: today)

        XCTAssertEqual(totals[1], summary.paidMinutes)
    }

    func testDaysNotHandedInAddNothing() {
        let layout = october()

        let totals = CalendarWeekTotals.minutes(of: layout, days: [], calendar: calendar, countingThrough: nil)

        XCTAssertEqual(totals, [0, 0, 0, 0, 0])
    }

    // MARK: - The week's list

    func testTheListHasTheWrittenTheMissingAndTheWorkingDaysToCome() {
        let layout = MonthLayout.week(containing: Fixture.date(2026, 10, 28), calendar: calendar, includesWeekends: true)
        let records = [
            worked(Fixture.date(2026, 10, 26)),
            worked(Fixture.date(2026, 10, 28)),
            DayRecord(date: Fixture.date(2026, 10, 30), dayTypeID: .vacation)
        ]
        let week = days(records, layout: layout)

        let rows = CalendarWeekList.rows(week, today: Fixture.date(2026, 10, 29))

        XCTAssertEqual(rows.map(\.id), [26, 27, 28, 29, 30].map { Fixture.date(2026, 10, $0).key },
                       "the weekend with nothing on it is left out")
        XCTAssertEqual(rows.map(\.status), [.written, .missing, .written, .notYet, .written])
    }

    func testAWeekendDayWorkedIsListed() {
        let layout = MonthLayout.week(containing: Fixture.date(2026, 10, 28), calendar: calendar, includesWeekends: true)
        let week = days([worked(Fixture.date(2026, 10, 31))], layout: layout)

        let rows = CalendarWeekList.rows(week, today: Fixture.date(2026, 11, 2))

        XCTAssertTrue(rows.contains { $0.id == Fixture.date(2026, 10, 31).key && $0.status == .written })
        XCTAssertFalse(rows.contains { $0.id == Fixture.date(2026, 11, 1).key })
    }

    func testDaysBeforeTheBalanceStartsAreNotMissing() {
        let layout = MonthLayout.week(containing: Fixture.date(2026, 10, 28), calendar: calendar, includesWeekends: true)
        let engine = Fixture.engine(calendar: calendar, firstRecorded: Fixture.date(2026, 10, 28))
        let record = worked(Fixture.date(2026, 10, 28))
        let week = engine.days(in: CalendarWeekTotals.span(of: layout, calendar: calendar),
                               records: [record.date.key: record], holidays: [])

        let rows = CalendarWeekList.rows(week, today: Fixture.date(2026, 10, 29))

        XCTAssertEqual(rows.map(\.id), [28, 29, 30].map { Fixture.date(2026, 10, $0).key })
    }

    func testTheSitesOfASplitDayAreInTheOrderTheyWereWorked() {
        let first = UUID()
        let second = UUID()
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [
            Shift(start: Fixture.time(7), end: Fixture.time(11), siteID: first),
            Shift(start: Fixture.time(11), end: Fixture.time(13), siteID: second),
            Shift(start: Fixture.time(13), end: Fixture.time(15), siteID: first),
            Shift(start: Fixture.time(15), end: Fixture.time(16))
        ])
        let day = Fixture.engine(calendar: calendar).day(Fixture.workingTuesday, record: record, holidays: [])

        XCTAssertEqual(CalendarWeekList.siteIDs(of: day), [first, second])
    }

    func testAWeekRowsDateIsTheShortWeekdayAndTheDay() {
        let formatting = CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)
        let label = formatting.shortWeekdayAndDay(Fixture.date(2026, 10, 26))

        XCTAssertTrue(label.contains("Mon"), label)
        XCTAssertTrue(label.contains("26"), label)
        XCTAssertFalse(label.contains("Oct"), "the week is the screen's title: \(label)")
    }
}
