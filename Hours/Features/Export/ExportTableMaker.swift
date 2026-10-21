import Foundation
import SwiftData

/// The two builds of a report the export screen needs: one for the file, one
/// for the screen.
///
/// Files want an empty cell where there is nothing; the preview reads better
/// with a dash. Everything else about the two is the same table, which is
/// what keeps the preview honest about the file.
struct ExportTables {
    var file: ReportTable
    var preview: ReportTable

    /// Whether there is anything to share. A site's sheet always ends with
    /// its two summary rows, so a month with no site days has those and
    /// nothing else.
    var hasContent: Bool {
        file.rows.count > min(max(file.trailingSummaryRows, 0), file.rows.count)
    }
}

/// Reads what a report needs from the store and builds it.
///
/// Constructed from a view's `modelContext`, so always used on the main
/// actor, as the repositories it reads through are.
struct ExportTableMaker {
    let context: ModelContext
    let settings: AppSettings
    let calendar: Calendar

    // MARK: - Your hours

    func personal(range: CalendarDateRange, title: String, period: String) -> ExportTables {
        let repository = WorkdayRepository(context: context)
        let holidays = repository.holidayRules()
        let engine = PeriodEngine(settings: settings, calendar: calendar)
        let days = engine.days(in: range, records: repository.records(in: range), holidays: holidays)
        let opening = carriedBalance(before: range, repository: repository, holidays: holidays, engine: engine)
        let today = CalendarDate.today(in: calendar)

        func build(_ placeholder: String) -> ReportTable {
            ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(
                    days: days,
                    range: range,
                    title: title,
                    period: period,
                    openingBalanceMinutes: opening,
                    countingThrough: today
                )
        }
        return ExportTables(file: build(""), preview: build("—"))
    }

    /// The balance carried into the range, so a running-balance column starts
    /// from the truth rather than from zero.
    ///
    /// Through the engine's `balanceCarried`, the same rule as the running
    /// balance on the statistics screen and closing a year. This used to
    /// count from the balance start date with the opening balance and ignore
    /// a closed year, so the column for January after a capped close started
    /// from the uncapped total.
    ///
    /// Worked out only when something prints it: the running-balance column,
    /// or the summary's "balance carried forward", which appears when an
    /// opening balance is set. That line used to print the opening balance
    /// plus the range, leaving out every month in between.
    private func carriedBalance(
        before range: CalendarDateRange,
        repository: WorkdayRepository,
        holidays: [HolidayRule],
        engine: PeriodEngine
    ) -> Int {
        guard settings.effectiveExportColumns.contains(.cumulativeBalance) || settings.openingBalanceMinutes != 0 else {
            return 0
        }
        return engine.balanceCarried(
            into: range,
            firstRecorded: repository.recordedDateBounds()?.first,
            holidays: holidays,
            countingThrough: CalendarDate.today(in: calendar),
            records: { repository.records(in: $0) }
        )
    }

    // MARK: - A site's month

    func site(_ site: Site, month: YearMonth) -> ExportTables {
        let repository = SiteRepository(context: context)
        let range = month.range(in: calendar)
        // Hidden people stay on the sheet: hiding only stops them being
        // offered for new days, and they worked the days they worked.
        let crew = repository.crew(for: site.id, includeHidden: true)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = repository.siteDays(siteID: site.id, in: range).map { calculator.compute($0) }

        func build(_ placeholder: String) -> ReportTable {
            SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(site: site, crew: crew, results: results, range: range)
        }
        return ExportTables(file: build(""), preview: build("—"))
    }
}
