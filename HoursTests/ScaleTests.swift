import XCTest
@testable import Hours

/// What the engine costs on a decade of hours.
///
/// The running balance is recomputed from every day ever recorded, on purpose:
/// storing it would mean correcting a day in the past left a stale total
/// behind. `CumulativeBalanceCard` reads it from a computed property, so the
/// whole history is walked on every render of that card.
///
/// That is a deliberate trade of speed for correctness, and it is the right way
/// round. What was missing is any idea of what the trade actually costs. These
/// measure it rather than guess: the numbers print into the CI log, and the
/// assertions are loose ceilings that only a change of a different order would
/// break. They are not a benchmark of the machine — a CI runner is a noisy
/// place — they are a tripwire for an algorithm that stops being linear.
final class ScaleTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Ten years of five-day weeks: about 2,600 recorded days.
    private func decade() -> (CalendarDateRange, [Int: DayRecord]) {
        let range = CalendarDateRange(start: Fixture.date(2016, 1, 1), end: Fixture.date(2025, 12, 31))
        var records: [Int: DayRecord] = [:]
        for date in range.days(in: calendar) {
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            records[date.key] = DayRecord(
                date: date,
                start: Fixture.time(8),
                end: date.day % 7 == 0 ? Fixture.time(18) : Fixture.time(16, 30),
                breaks: [.timed(from: Fixture.time(12), to: Fixture.time(12, 30))]
            )
        }
        return (range, records)
    }

    private func seconds(_ work: () -> Void) -> Double {
        let started = Date()
        work()
        return Date().timeIntervalSince(started)
    }

    func testADecadeOfHoursIsWalkedInReasonableTime() {
        let (range, records) = decade()
        let engine = Fixture.engine(calendar: calendar)

        var days: [DayComputation] = []
        let building = seconds { days = engine.days(in: range, records: records, holidays: []) }
        XCTAssertEqual(days.count, range.days(in: calendar).count)

        var balance = 0
        let reducing = seconds {
            balance = BalanceLedger.cumulative(over: days, openingMinutes: 0, startDate: nil)
        }

        print("----- scale -----")
        print("days in range           -> \(days.count)")
        print("records                 -> \(records.count)")
        print("engine.days             -> \(String(format: "%.3f", building))s")
        print("BalanceLedger.cumulative-> \(String(format: "%.4f", reducing))s")
        print("balance                 -> \(balance) minutes")
        print("----- end scale -----")

        // Ceilings, not targets. A CI runner under load is slow and erratic, so
        // these are set where only a change in the shape of the work — an
        // accidental nested loop, a per-day fetch — could reach them.
        XCTAssertLessThan(building, 10.0, "building a decade of days got dramatically slower")
        XCTAssertLessThan(reducing, 1.0, "reducing a decade of days got dramatically slower")
    }

    /// The monthly series walks the same days and buckets them. It backs the
    /// year chart, which is on screen at the same time as the running total.
    func testTheMonthlySeriesScalesWithTheSameData() {
        let (range, records) = decade()
        let days = Fixture.engine(calendar: calendar).days(in: range, records: records, holidays: [])

        var series: [MonthlyBalancePoint] = []
        let elapsed = seconds {
            series = BalanceLedger.monthlySeries(over: days, openingMinutes: 0, startDate: nil)
        }

        XCTAssertEqual(series.count, 120, "ten years is a hundred and twenty months")
        XCTAssertLessThan(elapsed, 1.0, "bucketing a decade of days got dramatically slower")
    }

    /// A decade exported at once, which is the largest report the app offers.
    func testADecadeExportsWithoutFallingOver() throws {
        let (range, records) = decade()
        let settings = Fixture.settings()
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: records, holidays: [])

        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Ten years", countingThrough: range.end)
        XCTAssertEqual(table.rows.count, days.count)

        var csv = Data()
        let elapsed = seconds { csv = CSVExporter.data(for: table, preferences: ExportPreferences()) }
        XCTAssertGreaterThan(csv.count, 100_000, "a decade of rows should be a substantial file")
        XCTAssertLessThan(elapsed, 10.0, "writing a decade of CSV got dramatically slower")
    }
}
