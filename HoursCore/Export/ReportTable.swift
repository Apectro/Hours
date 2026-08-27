import Foundation

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

    var isEmpty: Bool { rows.isEmpty }

    func headerTitles() -> [String] { columns.map { $0.heading(in: language) } }
}
