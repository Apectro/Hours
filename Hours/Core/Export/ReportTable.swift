import Foundation

/// One row of a report, already formatted.
struct ReportRow: Identifiable, Hashable, Sendable {
    var id: Int
    /// Parallel to the table's columns.
    var values: [String]
    /// Machine-readable values for the columns that hold numbers, so a
    /// spreadsheet gets real numbers rather than text it has to parse.
    var numbers: [Double?]
    var isWorkingDay: Bool
    var balanceMinutes: Int
    var hasEntry: Bool
}

/// A labelled figure in the totals block.
struct ReportTotal: Identifiable, Hashable, Sendable {
    var label: String
    var value: String
    var isEmphasised: Bool

    var id: String { label }
}

/// A finished report: columns, rows and totals.
///
/// CSV, XLSX and PDF are three renderings of this one value, which is what
/// keeps them consistent with each other and with the app.
struct ReportTable: Hashable, Sendable {
    var title: String
    var subtitle: String
    var columns: [ReportColumn]
    var rows: [ReportRow]
    var totals: [ReportTotal]

    var isEmpty: Bool { rows.isEmpty }

    func headerTitles() -> [String] { columns.map(\.title) }
}
