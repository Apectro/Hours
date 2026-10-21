import XCTest
@testable import Hours

/// The calculation audit, the running balance: the statistics card, the
/// export's running-balance column and closing a year must all start from
/// the same place and count the same days.
final class AuditBalanceTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Someone who started recording on Monday 1 June 2026, 9 h a day on
    /// weekdays through 31 December — half an hour over, every day.
    private func halfYear() -> [Int: DayRecord] {
        var records: [Int: DayRecord] = [:]
        for date in CalendarDateRange(start: Fixture.date(2026, 6, 1), end: Fixture.date(2026, 12, 31)).days(in: calendar) {
            let weekday = date.weekday(in: calendar)
            guard (2...6).contains(weekday) else { continue }
            records[date.key] = DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(17), breaks: [.duration(30)])
        }
        return records
    }

    private func balance(
        _ engine: PeriodEngine,
        through end: CalendarDate,
        records: [Int: DayRecord],
        countingThrough: CalendarDate? = nil
    ) -> Int {
        engine.runningBalance(
            through: end,
            firstRecorded: records.keys.min().flatMap(CalendarDate.init(key:)),
            holidays: [],
            countingThrough: countingThrough,
            records: { range in records.filter { range.dayKeys.contains($0.key) } }
        )
    }

    /// Closing 2026 counts from the first recorded day, as the running
    /// balance on the statistics screen does. The close used to count from
    /// 1 January four years earlier, so every working day before the person
    /// started using the app went in as eight hours short.
    func testClosingAYearCountsFromTheFirstRecordedDayLikeTheRunningBalance() {
        let records = halfYear()
        let engine = Fixture.engine(calendar: calendar)
        let workingDays = records.count

        let closing = balance(engine, through: Fixture.date(2026, 12, 31), records: records)
        XCTAssertEqual(closing, workingDays * 30)
    }

    /// After a capped close, January's export carries in what the close
    /// carried — not the uncapped total of every year before it.
    func testTheBalanceCarriedIntoARangeAfterAClosedYearIsWhatTheCloseCarried() {
        var records = halfYear()
        var settings = Fixture.settings()
        settings.carryOver = CarryOverPolicy(isEnabled: true, capMinutes: 20 * 60, surplusAbove: .paidOut)
        let before = Fixture.engine(settings: settings, calendar: calendar)
        let close = CarryOver.close(
            year: 2026,
            balance: balance(before, through: Fixture.date(2026, 12, 31), records: records),
            policy: settings.carryOver
        )
        XCTAssertEqual(close.carriedMinutes, 20 * 60, "the half year should have run over the cap")
        settings.yearCloses = [close]

        // A first week of January 2027 worked exactly to contract.
        for day in 4...8 {
            let date = Fixture.date(2027, 1, day)
            records[date.key] = DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(16, 30), breaks: [.duration(30)])
        }
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let january = YearMonth(year: 2027, month: 1).range(in: calendar)
        let carried = engine.balanceCarried(
            into: january,
            firstRecorded: Fixture.date(2026, 6, 1),
            holidays: [],
            countingThrough: Fixture.date(2027, 1, 8),
            records: { range in records.filter { range.dayKeys.contains($0.key) } }
        )
        XCTAssertEqual(carried, 20 * 60)
        XCTAssertEqual(
            balance(engine, through: Fixture.date(2027, 1, 8), records: records, countingThrough: Fixture.date(2027, 1, 8)),
            20 * 60 - 8 * 60 // 1 January is a Friday, recorded as nothing
        )
    }

    /// For any split of the record, what is carried into a range plus what
    /// the range adds is the running balance at its end — the identity the
    /// export's running-balance column depends on.
    func testCarriedInPlusTheRangeIsTheRunningBalanceAtItsEnd() {
        var generator = SeededGenerator(seed: 0xBA1A)
        var settings = Fixture.settings(openingBalanceMinutes: 95)
        settings.balanceStartDate = Fixture.date(2026, 3, 2)
        let engine = Fixture.engine(settings: settings, calendar: calendar)

        var records: [Int: DayRecord] = [:]
        for date in CalendarDateRange(start: Fixture.date(2026, 1, 5), end: Fixture.date(2026, 9, 30)).days(in: calendar)
        where Int.random(in: 0..<10, using: &generator) < 7 {
            let start = Int.random(in: 300...600, using: &generator)
            let length = Int.random(in: 120...660, using: &generator)
            records[date.key] = DayRecord(
                date: date,
                start: TimeOfDay(minutes: start),
                end: TimeOfDay(minutes: start + length),
                breaks: [.duration(Int.random(in: 0...60, using: &generator))]
            )
        }
        let lookup = { (range: CalendarDateRange) in records.filter { range.dayKeys.contains($0.key) } }
        let today = Fixture.date(2026, 9, 18)

        for _ in 0..<25 {
            let startOffset = Int.random(in: 0..<260, using: &generator)
            let start = Fixture.date(2026, 1, 1).adding(days: startOffset, in: calendar)
            let end = start.adding(days: Int.random(in: 0..<40, using: &generator), in: calendar)
            let range = CalendarDateRange(start: start, end: end)

            let carried = engine.balanceCarried(
                into: range,
                firstRecorded: Fixture.date(2026, 1, 5),
                holidays: [],
                countingThrough: today,
                records: lookup
            )
            let days = engine.days(in: range, records: lookup(range), holidays: [])
            let added = BalanceLedger.cumulative(
                over: days, openingMinutes: 0, startDate: settings.balanceStartDate, countingThrough: today
            )
            let atEnd = engine.runningBalance(
                through: end,
                firstRecorded: Fixture.date(2026, 1, 5),
                holidays: [],
                countingThrough: today,
                records: lookup
            )
            XCTAssertEqual(carried + added, atEnd, "\(range.start) – \(range.end)")
        }
    }
}
