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
    /// Status chips (In progress, Finished, Sent, Signed) and the small
    /// tinted labels beside them: one radius, so they read as one family.
    static let chipCornerRadius: CGFloat = 8

    /// Day cells are square-ish and comfortably above the 44pt touch minimum.
    static let dayCellHeight: CGFloat = 52
}

extension Color {
    /// A surplus. Green, because it is genuinely good news.
    ///
    /// The `HoursPositiveText` asset, not system green: system green on white
    /// is about 2:1 and unreadable as text in sunlight. The asset is a darker
    /// green in Light mode (#15803D, about 5:1) and system green in Dark.
    /// The asset is not named `HoursPositive` because Xcode generates a
    /// `Color` symbol for every colour set, and that one would clash with
    /// this property.
    static let hoursPositive = Color("HoursPositiveText")
    /// A shortfall. Deliberately orange, not red: being under your hours is a
    /// state to notice, not an error to be alarmed by.
    ///
    /// The `HoursWarningText` asset: a dark amber in Light mode (#B45309,
    /// about 5:1 on white, where system orange is about 2.2:1) and system
    /// orange in Dark. Safe for text.
    static let hoursNegative = Color("HoursWarningText")
    /// The bright orange, for fills and washes only (`opacity(0.10)` behind
    /// a row): never for text, which uses `hoursNegative`.
    static let hoursNegativeFill = Color.orange

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

    /// For one day at a time — the day editor and the site screen. A single
    /// day's figures do not depend on where the balance starts, so this one
    /// is not told; anything adding days up builds its engine with the first
    /// recorded day instead.
    var engine: PeriodEngine {
        PeriodEngine(settings: settings, calendar: workCalendar, firstRecorded: nil)
    }

    var durationFormatting: DurationFormatting {
        settings.displayFormatting
    }
}
