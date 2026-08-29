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

    var title: String { label(in: .device) }

    func label(in language: ExportLanguage) -> String {
        switch self {
        case .fileExport: return language(.proTimesheets)
        case .widgets: return language(.proWidgets)
        case .multipleJobs: return language(.proMultipleJobs)
        case .rangeEditing: return language(.proRangeEditing)
        case .iCloudSync: return language(.proICloudSync)
        }
    }

    var explanation: String { explanation(in: .device) }

    func explanation(in language: ExportLanguage) -> String {
        switch self {
        case .fileExport: return language(.proTimesheetsExplained)
        case .widgets: return language(.proWidgetsExplained)
        case .multipleJobs: return language(.proMultipleJobsExplained)
        case .rangeEditing: return language(.proRangeEditingExplained)
        case .iCloudSync: return language(.proICloudSyncExplained)
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
