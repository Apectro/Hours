import XCTest
@testable import Hours

/// The calculation audit, exports: every figure in a file against the
/// app's own `PeriodSummary` for the same range.
final class AuditExportTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// August 2026, exported on Wednesday the 12th: a month in progress, with
    /// an excluded day, an opening balance and every figure column chosen.
    private func monthInProgress(
        columns: [ReportColumn] = [.date, .breakTime, .worked, .credited, .expected, .overtime, .balance, .cumulativeBalance],
        durationStyle: DurationStyle = .clock
    ) -> (table: ReportTable, summary: PeriodSummary, settings: AppSettings) {
        var settings = Fixture.settings()
        settings.export.columns = columns
        settings.export.durationStyle = durationStyle
        settings.export.includeEmptyDays = true

        var records: [Int: DayRecord] = [:]
        for day in 3...7 {
            let date = Fixture.date(2026, 8, day)
            records[date.key] = DayRecord(
                date: date, start: Fixture.time(8), end: Fixture.time(17, 30), breaks: [.duration(30)]
            )
        }
        records[Fixture.date(2026, 8, 10).key] = DayRecord(
            date: Fixture.date(2026, 8, 10), dayTypeID: .vacation
        )
        records[Fixture.date(2026, 8, 11).key] = DayRecord(
            date: Fixture.date(2026, 8, 11), start: Fixture.time(8), end: Fixture.time(15, 50), breaks: [.duration(30)]
        )
        records[Fixture.date(2026, 8, 12).key] = DayRecord(
            date: Fixture.date(2026, 8, 12), start: Fixture.time(6), end: Fixture.time(18), isIncluded: false
        )

        let range = YearMonth(year: 2026, month: 8).range(in: calendar)
        let today = Fixture.date(2026, 8, 12)
        let days = Fixture.engine(settings: settings, calendar: calendar)
            .days(in: range, records: records, holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "August 2026", openingBalanceMinutes: 60, countingThrough: today)
        let summary = PeriodAggregator.summarize(days, range: range, countingThrough: today)
        return (table, summary, settings)
    }

    /// Every figure on the XLSX "Total" row, by column index.
    private func xlsxTotalRow(_ table: ReportTable, settings: AppSettings) -> [Int: Int] {
        let package = String(
            decoding: XLSXWriter.data(for: table, preferences: settings.export),
            as: UTF8.self
        )
        // Style 15 is the ruled total under the days.
        let pattern = #"<c r="([A-Z]+)\d+" s="15">(?:<f>[^<]*</f>)?<v>(-?[0-9.]+)</v></c>"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var figures: [Int: Int] = [:]
        let whole = NSRange(package.startIndex..., in: package)
        for match in regex.matches(in: package, range: whole) {
            let letter = String(package[Range(match.range(at: 1), in: package)!])
            let value = Double(package[Range(match.range(at: 2), in: package)!])!
            let index = Int(letter.unicodeScalars.first!.value) - 65
            figures[index] = Int((value * 1440).rounded())
        }
        return figures
    }

    // MARK: - The workbook's total row

    /// The PDF's total row, the summary block and the tiles all stop at
    /// today; the workbook's total row added up every row instead — so on a
    /// month in progress it reported the expected hours and the shortfall of
    /// days not yet reached, counted an excluded day, and added up the
    /// running-balance column, which has no meaningful sum.
    func testTheWorkbookTotalRowSaysWhatTheSummarySays() {
        let (table, summary, settings) = monthInProgress()
        let figures = xlsxTotalRow(table, settings: settings)
        let index = { (column: ReportColumn) in table.columns.firstIndex(of: column)! }

        XCTAssertEqual(figures[index(.worked)], summary.workedMinutes, "worked")
        XCTAssertEqual(figures[index(.breakTime)], summary.breakMinutes, "breaks")
        XCTAssertEqual(figures[index(.credited)], summary.creditedMinutes, "credited")
        XCTAssertEqual(figures[index(.expected)], summary.expectedMinutes, "expected")
        XCTAssertEqual(figures[index(.overtime)], summary.overtimeMinutes, "overtime")
        XCTAssertEqual(figures[index(.balance)], summary.balanceMinutes, "balance")
        XCTAssertEqual(figures[index(.cumulativeBalance)], 60 + summary.balanceMinutes, "running balance")

        // And the PDF's total row, which is the same table's.
        let pdfTotal = table.totalRow!
        for (column, minutes) in figures {
            XCTAssertEqual(pdfTotal.minutes[column], minutes, "column \(table.columns[column])")
        }
    }

    /// Where the days do add up to the total, the total stays a formula, so
    /// correcting a Tuesday in the workbook still corrects it.
    func testAColumnThatAddsUpStaysASumFormula() {
        let (table, _, settings) = monthInProgress()
        let package = String(
            decoding: XLSXWriter.data(for: table, preferences: settings.export),
            as: UTF8.self
        )
        // Breaks: none on the excluded day and none to come, so the days add up.
        let breaks = XLSXWriter.columnName(table.columns.firstIndex(of: .breakTime)!)
        XCTAssertTrue(package.contains("<f>SUM(\(breaks)"), "the break total is no longer a formula")
        let running = XLSXWriter.columnName(table.columns.firstIndex(of: .cumulativeBalance)!)
        XCTAssertFalse(package.contains("<f>SUM(\(running)"), "the running balance is being added up")
    }

    // MARK: - The running balance with empty days left out

    /// Leaving empty days out of the file hides their rows, not their hours.
    /// A working day nobody recorded is still eight hours short in the
    /// summary's balance; the running-balance column, and the "balance
    /// carried forward" made from it, skipped it with its row.
    func testLeavingEmptyDaysOutDoesNotLeaveTheirShortfallOutOfTheRunningBalance() {
        var settings = Fixture.settings()
        settings.export.columns = [.date, .worked, .balance, .cumulativeBalance]
        settings.export.includeEmptyDays = false

        let range = CalendarDateRange(start: Fixture.workingMonday, end: Fixture.date(2026, 8, 7))
        let records: [Int: DayRecord] = [
            Fixture.workingMonday.key: DayRecord(
                date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(17, 30), breaks: [.duration(30)]
            )
            // Tuesday to Friday: nothing recorded.
        ]
        let days = Fixture.engine(settings: settings, calendar: calendar).days(in: range, records: records, holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Week", openingBalanceMinutes: 120)
        let summary = PeriodAggregator.summarize(days, range: range)

        XCTAssertEqual(table.rows.count, 1, "only Monday has anything to show")
        let running = table.columns.firstIndex(of: .cumulativeBalance)!
        XCTAssertEqual(table.totalRow?.minutes[running], 120 + summary.balanceMinutes)
        let carried = table.totals.first { $0.label == settings.export.language(.carriedForward) }
        XCTAssertEqual(carried?.minutes, 120 + summary.balanceMinutes)
    }
}
