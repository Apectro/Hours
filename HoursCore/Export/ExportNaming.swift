import Foundation

/// What an export is called: the report's title, its period in words, and
/// the name of the file.
///
/// The title and the period are in the export language, like everything else
/// in the file; the file name too, because it is the first thing the person
/// receiving it reads.
struct ExportNaming: Sendable {
    let settings: AppSettings
    let calendar: Calendar

    private var language: ExportLanguage { settings.export.language }

    /// Months and weekdays inside the report come from the export language,
    /// not the phone's.
    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: language.locale, calendar: calendar)
    }

    private var owner: String {
        settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "August 2026", "week of 3 Aug", "2026".
    func period(rangeKind: ExportRangeKind, anchor: CalendarDate, range: CalendarDateRange) -> String {
        switch rangeKind {
        case .day: return formatting.mediumDate(anchor)
        case .week: return "\(language(.weekOf)) \(formatting.mediumDate(range.start))"
        case .month: return formatting.monthTitle(anchor.yearMonth)
        case .year: return "\(anchor.year)"
        case .custom:
            return range.start == range.end
                ? formatting.mediumDate(range.start)
                : "\(formatting.mediumDate(range.start)) – \(formatting.mediumDate(range.end))"
        }
    }

    /// "Hours — August 2026".
    func reportTitle(rangeKind: ExportRangeKind, anchor: CalendarDate, range: CalendarDateRange) -> String {
        "\(language(.hours)) — \(period(rangeKind: rangeKind, anchor: anchor, range: range))"
    }

    /// What a timesheet file is called when nobody has said otherwise.
    ///
    /// Led by the person's name when they have given one, because a folder of
    /// timesheets from several people sorts by whose they are before it sorts
    /// by when. A plain hyphen, not an em dash: the sanitiser replaces
    /// anything a file name cannot hold, and the field should show the name
    /// the file will actually be given.
    func timesheetFileName(rangeKind: ExportRangeKind, range: CalendarDateRange) -> String {
        let period: String
        switch rangeKind {
        case .day: period = "\(range.start)"
        case .month: period = monthStamp(range.start.yearMonth)
        case .year: period = "\(range.start.year)"
        default: period = "\(range.start) to \(range.end)"
        }
        let word = language(.hours)
        return owner.isEmpty ? "\(word) \(period)" : "\(owner) - \(word) \(period)"
    }

    /// The site's name and the month, so a folder of them sorts by site and
    /// then by month.
    func siteFileName(_ site: Site, month: YearMonth) -> String {
        "\(site.name) \(monthStamp(month))"
    }

    private func monthStamp(_ month: YearMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }
}
