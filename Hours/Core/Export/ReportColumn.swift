import Foundation

/// A column that can appear in an exported report.
///
/// The set is shared by CSV, XLSX and PDF so the three formats can never drift
/// apart, and it is filtered by the user's feature toggles: a column for a
/// feature that is switched off is never offered and never emitted.
enum ReportColumn: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case date
    case weekday
    case dayType
    case start
    case end
    case breakTime
    case worked
    case credited
    case expected
    case overtime
    case balance
    case cumulativeBalance
    case holiday
    case location
    case tags
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date"
        case .weekday: return "Day"
        case .dayType: return "Type"
        case .start: return "Start"
        case .end: return "End"
        case .breakTime: return "Break"
        case .worked: return "Worked"
        case .credited: return "Paid absence"
        case .expected: return "Expected"
        case .overtime: return "Overtime"
        case .balance: return "Balance"
        case .cumulativeBalance: return "Running balance"
        case .holiday: return "Holiday"
        case .location: return "Location"
        case .tags: return "Tags"
        case .note: return "Notes"
        }
    }

    /// Numeric columns are right-aligned in the PDF and typed as numbers in
    /// XLSX when a decimal duration style is selected.
    var isNumeric: Bool {
        switch self {
        case .worked, .credited, .expected, .overtime, .balance, .cumulativeBalance: return true
        default: return false
        }
    }

    var isDuration: Bool { isNumeric || self == .breakTime }

    /// A sensible default order; the user can reorder and disable columns.
    static let defaultSelection: [ReportColumn] = [
        .date, .weekday, .dayType, .start, .end, .breakTime, .worked, .expected, .overtime, .note
    ]
}
