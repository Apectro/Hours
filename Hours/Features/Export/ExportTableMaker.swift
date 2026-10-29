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
    /// The sites your hours in the range were worked on, in the order first
    /// worked: the export screen offers its Sites picker for more than one.
    var sites: [Site] = []

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

    /// - Parameter siteFilter: only this site's hours, from the Sites picker.
    func personal(range: CalendarDateRange, title: String, period: String, siteFilter: UUID? = nil) -> ExportTables {
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

        // Each site's address: for the Location column, when it is on, of a
        // day with no location of its own, and for the "By site" block and a
        // sheet filtered to one site. Names for the Site column (1.2).
        let allSites = SiteRepository(context: context).sites(includeArchived: true)
        let siteAddresses = Dictionary(allSites.map { ($0.id, $0.address) }, uniquingKeysWith: { first, _ in first })
        let siteNames = Dictionary(allSites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let worked = ReportBuilder.siteIDs(in: days)
        // A filter to a site the range no longer has falls back to all.
        let filter = siteFilter.flatMap { worked.count > 1 && worked.contains($0) ? $0 : nil }

        func build(_ placeholder: String) -> ReportTable {
            var builder = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
            builder.siteAddresses = siteAddresses
            builder.siteNames = siteNames
            builder.siteFilter = filter
            return builder
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
        var tables = ExportTables(file: build(""), preview: build("—"))
        tables.sites = worked.compactMap { id in allSites.first { $0.id == id } }
        return tables
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
        sites([site], month: month, includeDiary: includeDiary, includeSignatures: includeSignatures)
    }

    /// One director's sheet for the month of `sites`, in the order chosen
    /// (1.2): with one site, that site's sheet exactly; with several, the
    /// crews joined and each person's hours a day added up across them
    /// (`SiteSheetBuilder.makeTable(sites:)`), each site's diary under its
    /// name.
    func sites(_ chosen: [Site], month: YearMonth, includeDiary: Bool = true, includeSignatures: Bool = true) -> ExportTables {
        let repository = SiteRepository(context: context)
        // As stored now: the address may have been edited since the screen
        // that asked was opened.
        let sites = chosen.map { repository.site(id: $0.id) ?? $0 }
        let range = month.range(in: calendar)
        // Hidden people stay on the sheet: hiding only stops them being
        // offered for new days, and they worked the days they worked.
        let crew = sites.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let siteDays = sites.flatMap { repository.siteDays(siteID: $0.id, in: range) }
        let results = siteDays.map { calculator.compute($0) }

        let diaryRepository = SiteDiaryRepository(context: context)
        let signatures = sites.flatMap { diaryRepository.signatures(siteID: $0.id, month: month) }
        let diaryBuilder = SiteDiaryReportBuilder(settings: settings, calendar: calendar)
        let diaries = sites.map { site in
            diaryBuilder.make(
                diaries: diaryRepository.diaries(siteID: site.id, in: range),
                photos: diaryRepository.photoReferences(siteID: site.id, in: range),
                badWeatherStops: Set(siteDays.filter { $0.siteID == site.id && $0.isBadWeatherStop }.map(\.date)),
                range: range
            )
        }
        // One site's diary as it always was; several, each under its name.
        let diary = diaries.count == 1
            ? diaries[0]
            : SiteDiaryReport.combined(zip(sites, diaries).map { (siteName: $0.name, report: $1) })
        let printsDiary = includeDiary && !diary.isEmpty
        // For "On another site": the site's name on the sheet, archived too.
        let siteNames = Dictionary(
            repository.sites(includeArchived: true).map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        func build(_ placeholder: String) -> ReportTable {
            var table = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(
                    sites: sites,
                    crew: crew,
                    results: results,
                    range: range,
                    signatures: signatures,
                    includesSignatures: includeSignatures,
                    siteNames: siteNames
                )
            if printsDiary { table.diary = diary }
            return table
        }
        var tables = ExportTables(file: build(""), preview: build("—"))
        tables.hasDiary = !diary.isEmpty
        tables.photoIDs = printsDiary ? Set(diary.blocks.flatMap(\.photoIDs)) : []
        return tables
    }

    /// The crew's hours of every site with days in the month, by site, for
    /// the list of sites a sheet can take in. A site with days and no hours
    /// is there with zero.
    func siteMonthHours(month: YearMonth) -> [UUID: Int] {
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        var seen = Set<String>()
        var hours: [UUID: Int] = [:]
        for day in SiteRepository(context: context).siteDays(siteID: nil, in: month.range(in: calendar)) {
            // Sync can deliver a site day twice; the first one counts.
            guard seen.insert("\(day.siteID.uuidString)-\(day.date.key)").inserted else { continue }
            hours[day.siteID, default: 0] += calculator.compute(day).crewTotalMinutes
        }
        return hours
    }

    /// The diary photos with these ids, made small for the PDF. Only the ids
    /// not already in `cache` are read and re-encoded.
    func printPhotos(ids: Set<UUID>, sites: [Site], month: YearMonth, cache: [UUID: Data]) -> [UUID: Data] {
        var result = cache.filter { ids.contains($0.key) }
        var missing = ids.subtracting(result.keys)
        let repository = SiteDiaryRepository(context: context)
        for site in sites where !missing.isEmpty {
            let stored = repository.photoData(ids: missing, siteID: site.id, in: month.range(in: calendar))
            for (id, data) in stored {
                missing.remove(id)
                if let small = DiaryPhotoProcessor.printJPEG(from: data) { result[id] = small }
            }
        }
        return result
    }
}
