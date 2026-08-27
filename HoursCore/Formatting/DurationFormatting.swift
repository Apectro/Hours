import Foundation

/// How a length of time is written.
enum DurationStyle: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// `8h 30m`
    case hoursAndMinutes
    /// `8:30`
    case clock
    /// `8.50` — what payroll spreadsheets usually want.
    case decimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoursAndMinutes: return "8h 30m"
        case .clock: return "8:30"
        case .decimal: return "8.50"
        }
    }
}

/// Renders minute counts as text.
///
/// Signs matter here: a balance of zero is written without one, a surplus with
/// `+`, a shortfall with a minus. On screen that minus is a typographic minus
/// (U+2212) so columns of figures align; in exported files it is a plain
/// hyphen, because spreadsheets do not recognise the typographic one as
/// negative.
struct DurationFormatting: Hashable, Sendable {
    var style: DurationStyle
    var decimalSeparator: String
    var minusSign: String
    /// What "8h 30m" is called in the language the file is written in, and
    /// whether a space comes before the unit. English writes 8h 30m, German
    /// 8 Std 30 Min.
    var hourUnit: String
    var minuteUnit: String
    var unitSpacer: String

    init(
        style: DurationStyle = .hoursAndMinutes,
        decimalSeparator: String = ".",
        minusSign: String = "\u{2212}",
        hourUnit: String = "h",
        minuteUnit: String = "m",
        unitSpacer: String = ""
    ) {
        self.style = style
        self.decimalSeparator = decimalSeparator
        self.minusSign = minusSign
        self.hourUnit = hourUnit
        self.minuteUnit = minuteUnit
        self.unitSpacer = unitSpacer
    }

    /// For anything the user reads on screen.
    static let display = DurationFormatting()

    /// For files: ASCII hyphen so Excel, Numbers and Sheets parse negatives.
    static func export(
        style: DurationStyle,
        decimalSeparator: String,
        language: ExportLanguage = .english
    ) -> DurationFormatting {
        DurationFormatting(
            style: style,
            decimalSeparator: decimalSeparator,
            minusSign: "-",
            hourUnit: language.hourUnit,
            minuteUnit: language.minuteUnit,
            unitSpacer: language.unitSpacer
        )
    }

    func string(_ minutes: Int, showsSign: Bool = false) -> String {
        let magnitude = abs(minutes)
        let body: String
        switch style {
        case .hoursAndMinutes:
            body = hoursAndMinutesString(magnitude)
        case .clock:
            body = String(format: "%d:%02d", magnitude / 60, magnitude % 60)
        case .decimal:
            let value = Double(magnitude) / 60.0
            body = String(format: "%.2f", value).replacingOccurrences(of: ".", with: decimalSeparator)
        }

        if minutes < 0 { return minusSign + body }
        if showsSign && minutes > 0 { return "+" + body }
        return body
    }

    /// The signed form used for balances and overtime.
    func signedString(_ minutes: Int) -> String { string(minutes, showsSign: true) }

    private func hoursAndMinutesString(_ magnitude: Int) -> String {
        let hours = magnitude / 60
        let minutes = magnitude % 60
        func h(_ value: Int) -> String { "\(value)\(unitSpacer)\(hourUnit)" }
        func m(_ value: Int) -> String { "\(value)\(unitSpacer)\(minuteUnit)" }
        // Zero reads as "0h", not "0m": in a column of hours the unit should
        // not change just because the value happens to be nothing.
        if magnitude == 0 { return h(0) }
        if hours == 0 { return m(minutes) }
        if minutes == 0 { return h(hours) }
        return "\(h(hours)) \(m(minutes))"
    }

    /// Decimal hours, for spreadsheet cells that should hold a real number.
    static func decimalHours(_ minutes: Int) -> Double {
        (Double(minutes) / 60.0 * 100).rounded() / 100
    }
}
