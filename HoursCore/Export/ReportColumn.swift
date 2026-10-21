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
    case job
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
    /// "07:00–16:00": one person's arrival and departure in a single cell,
    /// for the director's sheet. Never offered for a timesheet, which has a
    /// start and an end column of its own and lets the person choose them.
    case times
    /// What each day earned, in the currency named in its heading. Never
    /// offered among the columns to choose: it is added at the end of a
    /// personal timesheet when Earnings is switched on in Export options, and
    /// a director's sheet never has it.
    case earnings

    var id: String { rawValue }

    /// What this column is called in the app, for the picker in Settings.
    var title: String { heading(in: .english) }

    /// What it is called at the top of an exported file.
    func heading(in language: ExportLanguage) -> String {
        language(term)
    }

    private var term: ExportTerm {
        switch self {
        case .date: return .date
        case .weekday: return .weekday
        case .dayType: return .dayType
        case .job: return .job
        case .start: return .start
        case .end: return .end
        case .breakTime: return .breakTime
        case .worked: return .worked
        case .credited: return .paidAbsence
        case .expected: return .expected
        case .overtime: return .overtime
        case .balance: return .balance
        case .cumulativeBalance: return .runningBalance
        case .holiday: return .holiday
        case .location: return .location
        case .tags: return .tags
        case .note: return .notes
        case .times: return .fromTo
        case .earnings: return .earnings
        }
    }

    /// Numeric columns are right-aligned in the PDF and typed as numbers in
    /// XLSX when a decimal duration style is selected.
    var isNumeric: Bool {
        switch self {
        case .worked, .credited, .expected, .overtime, .balance, .cumulativeBalance, .earnings: return true
        default: return false
        }
    }

    /// An amount of money is a figure but not a length of time.
    var isDuration: Bool { (isNumeric && self != .earnings) || self == .breakTime }

    /// Whether cutting this column's values short is untidy or wrong.
    ///
    /// A note that ends in an ellipsis is a note somebody can go and read in
    /// the app. A date, a clock time or a figure that ends in one is a
    /// document that misinforms, and there is no reading it any other way.
    /// So the columns holding free text give up their room first, and the
    /// rest keep theirs.
    var mayTruncate: Bool {
        switch self {
        case .note, .location, .tags, .job, .holiday: return true
        // A clock time cut short is a wrong time, as a date is a wrong date.
        default: return false
        }
    }

    /// A sensible default order; the user can reorder and disable columns.
    static let defaultSelection: [ReportColumn] = [
        .date, .weekday, .dayType, .start, .end, .breakTime, .worked, .expected, .overtime, .note
    ]
}
