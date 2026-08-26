import Foundation

/// The parts of the app that are paid for.
///
/// One rule decides what may appear in this list, and it is worth stating
/// before the list itself: **Pro gates producing and creating, never viewing or
/// keeping.** Someone whose subscription lapsed can still open every day they
/// ever recorded, still see their balance, and still take the whole lot out as
/// a backup file. What they lose is the convenience of a formatted timesheet
/// and the ability to set more up.
///
/// That is not only decency. An app that locks a person out of their own work
/// record is one App Review notices, and it is the sort of thing people write
/// one-star reviews about for years.
enum ProFeature: String, CaseIterable, Codable, Sendable, Identifiable {
    /// CSV, XLSX and PDF. Deliberately *not* the JSON backup — see
    /// `alwaysFree` below.
    case fileExport
    case widgets
    case multipleJobs
    case rangeEditing
    case iCloudSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fileExport: return "Timesheets"
        case .widgets: return "Widgets"
        case .multipleJobs: return "More than one job"
        case .rangeEditing: return "Edit a range at once"
        case .iCloudSync: return "iCloud sync"
        }
    }

    var explanation: String {
        switch self {
        case .fileExport:
            return "Hand your hours to payroll as a spreadsheet or a PDF, laid out the way you choose."
        case .widgets:
            return "Today's hours and the month's balance on your Home Screen and Lock Screen."
        case .multipleJobs:
            return "Two jobs on the same Tuesday, each with its own contracted week."
        case .rangeEditing:
            return "Book a fortnight of leave in one pass instead of ten trips through the editor."
        case .iCloudSync:
            return "The same hours on your phone and your iPad, through your own iCloud."
        }
    }

    var symbolName: String {
        switch self {
        case .fileExport: return "tablecells"
        case .widgets: return "square.grid.2x2"
        case .multipleJobs: return "briefcase"
        case .rangeEditing: return "calendar.badge.plus"
        case .iCloudSync: return "icloud"
        }
    }

    /// The things that stay free whatever happens, named here so that adding a
    /// case above without thinking has to argue with this list first.
    ///
    /// Recording hours, reading them back, the balance, and the backup file
    /// that gets every last one of them off the device.
    static let alwaysFree = [
        "Recording and editing your hours",
        "The calendar, the balance and every total",
        "Reminders about days you have not filled in",
        "The backup file, which holds everything you ever recorded",
    ]
}
