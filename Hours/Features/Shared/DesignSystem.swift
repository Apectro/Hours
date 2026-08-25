import SwiftUI
import UIKit

/// The spacing scale. Four values, used everywhere, so rhythm stays consistent
/// without anyone having to remember a number.
enum Metrics {
    static let tiny: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24

    static let cornerRadius: CGFloat = 14
    static let smallCornerRadius: CGFloat = 10

    /// Day cells are square-ish and comfortably above the 44pt touch minimum.
    static let dayCellHeight: CGFloat = 52
}

extension Color {
    /// A surplus. Green, because it is genuinely good news.
    static let hoursPositive = Color.green
    /// A shortfall. Deliberately orange, not red: being under your hours is a
    /// state to notice, not an error to be alarmed by.
    static let hoursNegative = Color.orange

    static var hoursCanvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var hoursSurface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var hoursHairline: Color { Color(uiColor: .separator) }
    static var hoursSubdued: Color { Color(uiColor: .tertiaryLabel) }

    /// The colour for a signed balance, including the zero case.
    static func hoursBalance(_ minutes: Int) -> Color {
        if minutes > 0 { return .hoursPositive }
        if minutes < 0 { return .hoursNegative }
        return .secondary
    }
}

extension TypeTint {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .indigo: return .indigo
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .indigo: return "Indigo"
        case .brown: return "Brown"
        case .gray: return "Gray"
        }
    }
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Font {
    /// Figures read better with rounded digits, and monospaced digits stop
    /// columns of numbers from jittering as they change.
    static func hoursFigure(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

extension SettingsStore {
    /// The calendar every date computation in the UI shares.
    var workCalendar: Calendar {
        settings.calendar.makeCalendar()
    }

    var dateFormatting: CalendarFormatting {
        CalendarFormatting(locale: .current, calendar: workCalendar)
    }

    var engine: PeriodEngine {
        PeriodEngine(settings: settings, calendar: workCalendar)
    }

    var durationFormatting: DurationFormatting {
        settings.displayFormatting
    }
}
