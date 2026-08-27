import Foundation

/// How exported files are shaped. Defaults are chosen for spreadsheet
/// round-tripping, not for prettiness.
struct ExportPreferences: Hashable, Codable, Sendable {
    var dateStyle: ExportDateStyle
    var timeStyle: ExportTimeStyle
    var durationStyle: DurationStyle
    var fieldSeparator: CSVSeparator
    var decimalSeparator: DecimalSeparator
    /// Excel on Windows needs a byte-order mark to read UTF-8 CSV correctly.
    var includeByteOrderMark: Bool
    var includeSummaryRows: Bool
    var includeEmptyDays: Bool
    var columns: [ReportColumn]
    var defaultRange: ExportRangeKind
    /// The language the file is written in, which need not be the one the
    /// app is in — the person reading a timesheet is often not the person who
    /// recorded it.
    var language: ExportLanguage
    /// Whose hours these are, printed on the timesheet.
    ///
    /// A timesheet that reaches a payroll department with no name on it is a
    /// timesheet somebody has to ask about. Empty by default, because the app
    /// has no account and does not otherwise know who you are — and an empty
    /// name prints nothing rather than a blank line.
    var ownerName: String

    init(
        dateStyle: ExportDateStyle = .iso,
        timeStyle: ExportTimeStyle = .twentyFourHour,
        durationStyle: DurationStyle = .hoursAndMinutes,
        fieldSeparator: CSVSeparator = .comma,
        decimalSeparator: DecimalSeparator = .point,
        includeByteOrderMark: Bool = true,
        includeSummaryRows: Bool = true,
        includeEmptyDays: Bool = true,
        columns: [ReportColumn] = ReportColumn.defaultSelection,
        defaultRange: ExportRangeKind = .month,
        language: ExportLanguage = .device,
        ownerName: String = ""
    ) {
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
        self.durationStyle = durationStyle
        self.fieldSeparator = fieldSeparator
        self.decimalSeparator = decimalSeparator
        self.includeByteOrderMark = includeByteOrderMark
        self.includeSummaryRows = includeSummaryRows
        self.includeEmptyDays = includeEmptyDays
        self.columns = columns.isEmpty ? ReportColumn.defaultSelection : columns
        self.defaultRange = defaultRange
        self.language = language
        self.ownerName = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case dateStyle, timeStyle, durationStyle, fieldSeparator, decimalSeparator
        case includeByteOrderMark, includeSummaryRows, includeEmptyDays, columns, defaultRange
        case ownerName, language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ExportPreferences()
        self.init(
            dateStyle: container.lenient(.dateStyle, defaults.dateStyle),
            timeStyle: container.lenient(.timeStyle, defaults.timeStyle),
            durationStyle: container.lenient(.durationStyle, defaults.durationStyle),
            fieldSeparator: container.lenient(.fieldSeparator, defaults.fieldSeparator),
            decimalSeparator: container.lenient(.decimalSeparator, defaults.decimalSeparator),
            includeByteOrderMark: container.lenient(.includeByteOrderMark, defaults.includeByteOrderMark),
            includeSummaryRows: container.lenient(.includeSummaryRows, defaults.includeSummaryRows),
            includeEmptyDays: container.lenient(.includeEmptyDays, defaults.includeEmptyDays),
            columns: container.lenient(.columns, defaults.columns),
            defaultRange: container.lenient(.defaultRange, defaults.defaultRange),
            language: container.lenient(.language, defaults.language),
            ownerName: container.lenient(.ownerName, defaults.ownerName)
        )
    }
}

enum ExportDateStyle: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// `2026-08-04` — unambiguous and sorts correctly as text everywhere.
    case iso
    /// `04.08.2026`
    case dotted
    /// `04/08/2026`
    case slashed
    /// `08/04/2026`
    case slashedUS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iso: return "2026-08-04"
        case .dotted: return "04.08.2026"
        case .slashed: return "04/08/2026"
        case .slashedUS: return "08/04/2026"
        }
    }

    func string(for date: CalendarDate) -> String {
        switch self {
        case .iso: return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
        case .dotted: return String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
        case .slashed: return String(format: "%02d/%02d/%04d", date.day, date.month, date.year)
        case .slashedUS: return String(format: "%02d/%02d/%04d", date.month, date.day, date.year)
        }
    }
}

enum ExportTimeStyle: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case twentyFourHour
    case twelveHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentyFourHour: return "16:30"
        case .twelveHour: return "4:30 PM"
        }
    }

    func string(for time: TimeOfDay) -> String {
        switch self {
        case .twentyFourHour:
            return String(format: "%02d:%02d", time.hour, time.minute)
        case .twelveHour:
            let suffix = time.hour < 12 ? "AM" : "PM"
            var hour = time.hour % 12
            if hour == 0 { hour = 12 }
            return String(format: "%d:%02d %@", hour, time.minute, suffix)
        }
    }
}

enum CSVSeparator: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case comma
    case semicolon
    case tab

    var id: String { rawValue }

    var character: String {
        switch self {
        case .comma: return ","
        case .semicolon: return ";"
        case .tab: return "\t"
        }
    }

    var title: String {
        switch self {
        case .comma: return "Comma  ,"
        case .semicolon: return "Semicolon  ;"
        case .tab: return "Tab"
        }
    }
}

enum DecimalSeparator: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case point
    case comma

    var id: String { rawValue }

    var character: String {
        switch self {
        case .point: return "."
        case .comma: return ","
        }
    }

    var title: String {
        switch self {
        case .point: return "Point  8.50"
        case .comma: return "Comma  8,50"
        }
    }
}

enum ExportRangeKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case day
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .custom: return "Custom"
        }
    }
}
