import Foundation

/// What a row is for, which decides how it is drawn and, in a workbook,
/// whether its figures are values or formulas.
enum ReportRowRole: String, Hashable, Sendable {
    /// One day.
    case day
    /// A sum of the days above it, ruled off from them.
    case total
    /// A count of days, beneath a total.
    case count
}

/// One row of a report, already formatted.
struct ReportRow: Identifiable, Hashable, Sendable {
    var id: Int
    /// Parallel to the table's columns.
    var values: [String]
    /// The same columns as minutes, for the ones that hold a duration, so a
    /// spreadsheet gets a real number rather than text it has to parse.
    /// Minutes rather than hours because minutes are what the engine counts
    /// in, and dividing here would round once per cell.
    var minutes: [Int?]
    var isWorkingDay: Bool
    var balanceMinutes: Int
    var hasEntry: Bool
    /// A day of paid absence — sick, vacation, a public holiday — which the
    /// printed page washes faintly so it reads apart from both a working day
    /// and a weekend.
    var isAbsence: Bool = false
    var role: ReportRowRole = .day
    /// Columns whose value differs from what the row would lead a reader to
    /// expect, drawn in the accent colour: on the director's sheet, someone
    /// who came late or left early.
    var flagged: Set<Int> = []
    /// Column groups whose first value is drawn once across the whole group
    /// rather than cell by cell: on the director's sheet, the dash for
    /// someone who was not there that day.
    var mergedGroups: Set<Int> = []
    /// Columns that hold a plain number rather than a duration — a quantity
    /// of material — so a workbook writes a number it can add up. Empty for
    /// every report that has none.
    var numbers: [Double?] = []
}

/// A run of neighbouring columns under one heading: on the director's sheet,
/// a person's times and hours under their name.
struct ReportColumnGroup: Hashable, Sendable {
    var title: String
    var span: Int
}

/// One of the figures in the boxes at the top of a printed report.
struct ReportTile: Identifiable, Hashable, Sendable {
    var label: String
    var value: String
    /// Drawn in red, on red: a balance below zero.
    var isNegative: Bool = false

    var id: String { label }
}

/// Which report a table is, for the few places the two are drawn differently.
enum ReportKind: String, Hashable, Sendable {
    /// One person's days, from `ReportBuilder`.
    case timesheet
    /// A site's month, one group of columns per person, from `SiteSheetBuilder`.
    case siteSheet
    /// A site's diary as a table, the workbook's second sheet; from
    /// `SiteDiaryReport.table(language:)`.
    case siteDiary
    /// Extra work for the boss: its material and its jobs, from
    /// `ExtraWorkDocument`.
    case extraWork
}

/// A labelled figure in the totals block.
struct ReportTotal: Identifiable, Hashable, Sendable {
    var label: String
    var value: String
    var isEmphasised: Bool
    /// Set when the figure is a duration; the workbook writes it as a number.
    var minutes: Int?
    /// Set when the figure is a count of days rather than an amount of time.
    var count: Int?

    init(
        label: String,
        value: String,
        isEmphasised: Bool,
        minutes: Int? = nil,
        count: Int? = nil
    ) {
        self.label = label
        self.value = value
        self.isEmphasised = isEmphasised
        self.minutes = minutes
        self.count = count
    }

    var id: String { label }
}

/// A finished report: columns, rows and totals.
///
/// CSV, XLSX and PDF are three renderings of this one value, which is what
/// keeps them consistent with each other and with the app.
struct ReportTable: Hashable, Sendable {
    var title: String
    var subtitle: String
    /// Whose hours these are. Empty prints nothing at all rather than a blank
    /// line where a name would be.
    var ownerName: String = ""
    /// The language the renderers write their own words in. The rows and the
    /// totals arrive already translated; this is for "Summary", "Total" and
    /// the page footer, which only exist once a format is chosen.
    var language: ExportLanguage = .device
    var columns: [ReportColumn]
    var rows: [ReportRow]
    var totals: [ReportTotal]
    /// Column titles that replace the ones the columns would give, for a
    /// report whose columns are people rather than kinds of figure (the
    /// director's sheet has one `.worked` column per person). Ignored unless
    /// there is exactly one per column.
    var headingOverrides: [String]? = nil
    /// How many of the last rows are summaries the builder already wrote
    /// (the director's sheet ends with a month total and a days-worked row).
    /// The workbook then adds no ruled "Total" row of its own, and keeps these
    /// rows out of the filter range so sorting never mixes them into the days.
    var trailingSummaryRows: Int = 0

    var kind: ReportKind = .timesheet
    /// The small line above the headline: "Timesheet", "Site hours · August
    /// 2026". Written in ordinary case; the page sets it in capitals.
    var eyebrow: String = ""
    /// The grey line under the headline. Empty falls back to the subtitle.
    var detail: String = ""
    var tiles: [ReportTile] = []
    /// Headings over runs of columns. Ignored unless their spans add up to
    /// exactly the columns, so a table that gets this wrong prints flat
    /// headings rather than misplaced ones.
    var columnGroups: [ReportColumnGroup] = []
    /// The ruled total under the days on the printed page, which agrees with
    /// the summary because it is made from it. The workbook writes its own,
    /// as formulas, and the CSV has none.
    var totalRow: ReportRow? = nil
    /// A sentence under the table explaining how to read it.
    var legend: String = ""
    /// The labels under the lines left to sign on.
    var signatures: [String] = []
    /// The site diary that follows the hours: pages of their own in the PDF,
    /// a sheet of its own in the workbook, and nothing in a CSV, which is one
    /// table by nature. `nil` or empty adds nothing.
    var diary: SiteDiaryReport? = nil
    /// A box per person with their signature, on the director's sheet once
    /// anyone has signed. Empty prints nothing.
    var signOff: [ReportSignOff] = []

    var isEmpty: Bool { rows.isEmpty }

    /// The big line at the top of the page. A timesheet is headed by whose
    /// hours they are, because that is what the person it is handed to looks
    /// for first; without a name it falls back to the report's own title.
    var headline: String {
        kind == .timesheet && !ownerName.isEmpty ? ownerName : title
    }

    /// The grey line under the headline.
    var byline: String { detail.isEmpty ? subtitle : detail }

    /// The groups, when they describe these columns exactly.
    var validGroups: [ReportColumnGroup] {
        let spans = columnGroups.map(\.span)
        guard !columnGroups.isEmpty, spans.allSatisfy({ $0 > 0 }), spans.reduce(0, +) == columns.count else {
            return []
        }
        return columnGroups
    }

    /// The column indices each valid group covers, in order.
    var groupRanges: [Range<Int>] {
        var start = 0
        return validGroups.map { group in
            defer { start += group.span }
            return start..<(start + group.span)
        }
    }

    /// One heading per column, for a format that has room for one row of
    /// them. A column inside a group of several is named after the group as
    /// well — "Ana hours" — so a CSV importer still knows whose hours they are.
    func headerTitles() -> [String] {
        let own = columnHeadings()
        let ranges = groupRanges
        guard !ranges.isEmpty else { return own }
        var titles = own
        for (group, range) in zip(validGroups, ranges) where range.count > 1 {
            for index in range {
                titles[index] = "\(group.title) \(language.inline(own[index]))"
            }
        }
        return titles
    }

    /// The columns' own headings, without their groups: the second heading
    /// row of a workbook.
    func columnHeadings() -> [String] {
        if let headingOverrides, headingOverrides.count == columns.count { return headingOverrides }
        return columns.map { $0.heading(in: language) }
    }

    /// The title of one column, honouring the overrides.
    func heading(at index: Int) -> String {
        let titles = headerTitles()
        return titles.indices.contains(index) ? titles[index] : ""
    }
}
