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
    /// A site month with a diary to offer: the export screen shows the
    /// "Include site diary" switch only then.
    var hasDiary = false
    /// The diary photos the file's PDF prints, by id. The bytes are read by
    /// the export screen, and only for a PDF.
    var photoIDs: Set<UUID> = []

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
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
        let days = engine.days(in: range, records: repository.records(in: range), holidays: holidays)
        let opening = carriedBalance(before: range, repository: repository, holidays: holidays, engine: engine)
        let today = CalendarDate.today(in: calendar)
        // Read only when the file will carry them; whole weeks, so a week cut
        // by the range keeps its overtime where it fell.
        let earnings = settings.export.includeEarnings
            ? engine.earnings(
                in: range,
                records: repository.records(in: engine.earningsRange(covering: range)),
                holidays: holidays,
                countingThrough: today
            )
            : nil

        func build(_ placeholder: String) -> ReportTable {
            ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(
                    days: days,
                    range: range,
                    title: title,
                    period: period,
                    openingBalanceMinutes: opening,
                    countingThrough: today,
                    earnings: earnings,
                    currencyCode: settings.money.currencyCode
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
            holidays: holidays,
            countingThrough: CalendarDate.today(in: calendar),
            records: { repository.records(in: $0) }
        )
    }

    // MARK: - A site's month

    /// - Parameters:
    ///   - includeDiary: whether the month's site diary follows the hours,
    ///     when it has one.
    ///   - includeSignatures: whether the sheet has a line to sign on and,
    ///     once anyone has signed, the crew's sign-off. Signing is optional.
    func site(_ site: Site, month: YearMonth, includeDiary: Bool = true, includeSignatures: Bool = true) -> ExportTables {
        let repository = SiteRepository(context: context)
        let range = month.range(in: calendar)
        // Hidden people stay on the sheet: hiding only stops them being
        // offered for new days, and they worked the days they worked.
        let crew = repository.crew(for: site.id, includeHidden: true)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let siteDays = repository.siteDays(siteID: site.id, in: range)
        let results = siteDays.map { calculator.compute($0) }

        let diaryRepository = SiteDiaryRepository(context: context)
        let signatures = diaryRepository.signatures(siteID: site.id, month: month)
        let diary = SiteDiaryReportBuilder(settings: settings, calendar: calendar).make(
            diaries: diaryRepository.diaries(siteID: site.id, in: range),
            photos: diaryRepository.photoReferences(siteID: site.id, in: range),
            badWeatherStops: Set(siteDays.filter(\.isBadWeatherStop).map(\.date)),
            range: range
        )
        let printsDiary = includeDiary && !diary.isEmpty

        func build(_ placeholder: String) -> ReportTable {
            var table = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(
                    site: site,
                    crew: crew,
                    results: results,
                    range: range,
                    signatures: signatures,
                    includesSignatures: includeSignatures
                )
            if printsDiary { table.diary = diary }
            return table
        }
        var tables = ExportTables(file: build(""), preview: build("—"))
        tables.hasDiary = !diary.isEmpty
        tables.photoIDs = printsDiary ? Set(diary.blocks.flatMap(\.photoIDs)) : []
        return tables
    }

    /// The diary photos with these ids, made small for the PDF. Only the ids
    /// not already in `cache` are read and re-encoded.
    func printPhotos(ids: Set<UUID>, site: Site, month: YearMonth, cache: [UUID: Data]) -> [UUID: Data] {
        var result = cache.filter { ids.contains($0.key) }
        let missing = ids.subtracting(result.keys)
        guard !missing.isEmpty else { return result }
        let stored = SiteDiaryRepository(context: context)
            .photoData(ids: missing, siteID: site.id, in: month.range(in: calendar))
        for (id, data) in stored {
            if let small = DiaryPhotoProcessor.printJPEG(from: data) { result[id] = small }
        }
        return result
    }
}
