import XCTest
@testable import Hours

/// Where the balance starts: the start date when one is set, otherwise the
/// first day anything was recorded.
///
/// Someone who installs the app on a Monday in the middle of October did not
/// spend the first half of the month eight hours short every day, and the
/// month, the running balance, the gaps and the widget must all agree on it.
final class BalanceStartTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Wednesday 21 October 2026. The week runs Monday 19 to Sunday 25.
    private let today = Fixture.date(2026, 10, 21)
    private let monday = Fixture.date(2026, 10, 19)

    /// Monday 9 h, Tuesday 10 h, Wednesday 9 h, no breaks: 4 h over a
    /// contract of 8 h a day.
    private var firstWeek: [Int: DayRecord] {
        let days = [
            Fixture.record(on: Fixture.date(2026, 10, 19), start: Fixture.time(7), end: Fixture.time(16)),
            Fixture.record(on: Fixture.date(2026, 10, 20), start: Fixture.time(7), end: Fixture.time(17)),
            Fixture.record(on: Fixture.date(2026, 10, 21), start: Fixture.time(7), end: Fixture.time(16)),
        ]
        return Dictionary(days.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var october: CalendarDateRange { YearMonth(year: 2026, month: 10).range(in: calendar) }

    private func monthSummary(_ engine: PeriodEngine, records: [Int: DayRecord]) -> PeriodSummary {
        engine.summary(in: october, records: records, holidays: [], countingThrough: today)
    }

    private func lookup(_ records: [Int: DayRecord]) -> (CalendarDateRange) -> [Int: DayRecord] {
        { range in records.filter { range.dayKeys.contains($0.key) } }
    }

    // MARK: - The month

    func testAMidMonthStarterIsOnlyCountedFromTheirFirstEntry() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)

        let summary = monthSummary(engine, records: firstWeek)

        XCTAssertEqual(summary.expectedMinutes, 3 * 480, "1 to 16 October are before the first entry")
        XCTAssertEqual(summary.workedMinutes, 28 * 60)
        XCTAssertEqual(summary.balanceMinutes, 4 * 60)
        XCTAssertEqual(summary.deficitMinutes, 0)
        XCTAssertEqual(summary.scheduledWorkingDays, 3)
    }

    func testAnExplicitStartDateEarlierThanTheFirstEntryWins() {
        var settings = Fixture.settings()
        // Thursday 15 October: Thursday and Friday count, empty, as 8 h short.
        settings.balanceStartDate = Fixture.date(2026, 10, 15)
        let engine = Fixture.engine(settings: settings, calendar: calendar, firstRecorded: monday)

        XCTAssertEqual(monthSummary(engine, records: firstWeek).balanceMinutes, 4 * 60 - 2 * 480)
    }

    func testAnExplicitStartDateLaterThanTheFirstEntryWins() {
        var settings = Fixture.settings()
        settings.balanceStartDate = Fixture.date(2026, 10, 20)
        let engine = Fixture.engine(settings: settings, calendar: calendar, firstRecorded: monday)

        // Monday's hour over is before the start: Tuesday +2 h, Wednesday +1 h.
        XCTAssertEqual(monthSummary(engine, records: firstWeek).balanceMinutes, 3 * 60)
    }

    /// The first recorded day the app hands in can be a moment out of date —
    /// read before a save that added an earlier day. A day with something on
    /// it is never before the start.
    func testADayRecordedBeforeTheGivenFirstDayStillCounts() {
        var records = firstWeek
        let earlier = Fixture.record(on: Fixture.date(2026, 10, 16), start: Fixture.time(8), end: Fixture.time(16))
        records[earlier.date.key] = earlier
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)

        let summary = monthSummary(engine, records: records)

        XCTAssertEqual(summary.workedMinutes, 36 * 60)
        XCTAssertEqual(summary.balanceMinutes, 4 * 60, "Friday 16th, 8 h on an 8 h day")
    }

    func testNothingRecordedMeansNoBalanceAndNoGaps() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: nil)

        let summary = monthSummary(engine, records: [:])
        XCTAssertEqual(summary.balanceMinutes, 0)
        XCTAssertEqual(summary.expectedMinutes, 0)

        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)
        let days = engine.days(in: window, records: [:], holidays: [])
        XCTAssertEqual(GapFinder.unrecordedWorkingDays(in: days, asOf: today), [])

        XCTAssertEqual(
            engine.runningBalance(through: today, holidays: [], countingThrough: today, records: lookup([:])),
            0
        )
    }

    // MARK: - Gaps

    func testDaysBeforeTheFirstEntryAreNotGaps() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)
        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)
        let days = engine.days(in: window, records: lookup(firstWeek)(window), holidays: [])

        XCTAssertEqual(GapFinder.unrecordedWorkingDays(in: days, asOf: today), [])
        let friday = days.first { $0.date == Fixture.date(2026, 10, 16) }
        XCTAssertEqual(friday?.isUnrecordedWorkingDay(asOf: today), false, "the calendar's dashed outline")
    }

    func testAnEmptyWorkingDayAfterTheFirstEntryIsStillAGap() {
        var records = firstWeek
        records.removeValue(forKey: Fixture.date(2026, 10, 20).key)
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)
        let window = GapFinder.window(endingAt: today, lookBackDays: 14, calendar: calendar)
        let days = engine.days(in: window, records: lookup(records)(window), holidays: [])

        XCTAssertEqual(GapFinder.unrecordedWorkingDays(in: days, asOf: today), [Fixture.date(2026, 10, 20)])
    }

    // MARK: - Every figure agrees

    func testTheRunningBalanceIsTheMonthsBalanceForAFirstMonth() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)

        let running = engine.runningBalance(
            through: today,
            holidays: [],
            countingThrough: today,
            records: lookup(firstWeek)
        )

        XCTAssertEqual(running, monthSummary(engine, records: firstWeek).balanceMinutes)
    }

    func testTheRunningBalanceHonoursAnEarlierExplicitStartDateToo() {
        var settings = Fixture.settings()
        settings.balanceStartDate = Fixture.date(2026, 10, 15)
        let engine = Fixture.engine(settings: settings, calendar: calendar, firstRecorded: monday)

        let running = engine.runningBalance(
            through: today,
            holidays: [],
            countingThrough: today,
            records: lookup(firstWeek)
        )

        XCTAssertEqual(running, 4 * 60 - 2 * 480)
    }

    func testWhatIsCarriedIntoNovemberIsOctobersBalance() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)
        let november = YearMonth(year: 2026, month: 11).range(in: calendar)

        let carried = engine.balanceCarried(into: november, holidays: [], countingThrough: today, records: lookup(firstWeek))

        XCTAssertEqual(carried, 4 * 60)
    }

    func testJobTotalsLeaveOutDaysBeforeTheStart() {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)
        let days = engine.days(in: october, records: firstWeek, holidays: [])

        let totals = engine.jobTotals(for: days, countingThrough: today)

        XCTAssertEqual(totals.first?.expectedMinutes, 3 * 480)
    }

    // MARK: - The widget

    /// The widget's month balance, through the file it is read from: the
    /// figure that showed as "0h month" on a phone whose calendar began on
    /// 19 October.
    func testTheWidgetsMonthBalanceStartsAtTheFirstEntry() throws {
        let engine = Fixture.engine(calendar: calendar, firstRecorded: monday)
        let days = engine.days(in: october, records: firstWeek, holidays: [])
        let summary = PeriodAggregator.summarize(days, range: october, countingThrough: today)
        let written = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 17))!
        let snapshot = WidgetSnapshot(
            generatedAt: written,
            isClockRunning: false,
            clockStartedAt: nil,
            clockJobName: nil,
            todayWorkedMinutes: 540,
            todayExpectedMinutes: 480,
            monthWorkedMinutes: summary.workedMinutes,
            monthExpectedMinutes: summary.expectedMinutes,
            monthBalanceMinutes: summary.balanceMinutes,
            showsBalance: true,
            unrecordedDayCount: 0,
            durationStyle: .hoursAndMinutes,
            isUnlocked: true,
            monthMarks: WidgetSnapshotBuilder.monthMarks(days, today: today)
        )

        let read = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        let glance = written.addingTimeInterval(15 * 60)

        XCTAssertEqual(read.monthBalance(at: glance, calendar: calendar), 4 * 60)
        XCTAssertEqual(
            read.monthMarks(at: glance, calendar: calendar).map(\.date).first,
            monday,
            "no squares owed for the days before the first entry"
        )
    }
}
