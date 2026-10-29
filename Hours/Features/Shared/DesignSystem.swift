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
    /// The old name for the orange, kept so every screen still compiles
    /// while the redesign moves them over. Say what you mean instead:
    /// `hoursAttention` for "look at this" (late, early, away, partly
    /// filled, rained off), `hoursMissing` for missing or minus. A minus
    /// balance is red now (`hoursBalance(_:)`), not this.
    static let hoursNegative = Color.hoursAttention
    /// The old name for `hoursAttentionFill`.
    static let hoursNegativeFill = Color.hoursAttentionFill

    // MARK: - The colour rule
    //
    // Every colour means one thing, everywhere. Blue (the accent): you can
    // tap it. Green: done, or in your favour. Orange: look at this. Red:
    // missing or minus. Grey: nothing expected. Text uses the asset colours,
    // which pass 4.5:1; the bright fills are for fills and washes only.

    /// Look at this: late, early, away, partly filled. Orange, for text.
    ///
    /// The `HoursWarningText` asset: a dark amber in Light mode (#B45309,
    /// about 5:1 on white, where system orange is about 2.2:1) and system
    /// orange in Dark. Safe for text.
    static let hoursAttention = Color("HoursWarningText")
    /// The bright orange, for fills and washes only (`opacity(0.10)` behind
    /// a row): never for text, which uses `hoursAttention`.
    static let hoursAttentionFill = Color.orange

    /// Missing or minus: a day nobody wrote, a balance under zero. Red, for
    /// text.
    ///
    /// The `HoursMissingText` asset: #B42318 in Light mode (about 6.5:1 on
    /// white, where system red is about 3.6:1) and system red in Dark.
    static let hoursMissing = Color("HoursMissingText")
    /// The bright red, for fills and washes only: never for text, which
    /// uses `hoursMissing`.
    static let hoursMissingFill = Color.red

    /// Done: written, signed, sent. The same green as `hoursPositive`, by
    /// another name where "done" is what it means.
    static let hoursDone = Color.hoursPositive

    static var hoursCanvas: Color { Color(uiColor: .systemGroupedBackground) }
    static var hoursSurface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var hoursHairline: Color { Color(uiColor: .separator) }
    static var hoursSubdued: Color { Color(uiColor: .tertiaryLabel) }

    /// The colour for a signed balance, including the zero case: green in
    /// your favour, red under zero (the colour rule's "minus"), and
    /// secondary for nothing either way.
    static func hoursBalance(_ minutes: Int) -> Color {
        if minutes > 0 { return .hoursPositive }
        if minutes < 0 { return .hoursMissing }
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

// MARK: - On site: Bigger buttons and High contrast

private struct BiggerButtonsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct HighContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Appearance › Bigger buttons: the daily actions' big buttons are drawn
    /// taller, for gloves. Set once at the root from `AppSettings`; read by
    /// `BigActionButtonStyle`.
    var biggerButtons: Bool {
        get { self[BiggerButtonsKey.self] }
        set { self[BiggerButtonsKey.self] = newValue }
    }

    /// Appearance › High contrast: secondary text and hairlines darker, for
    /// sunlight. Set once at the root from `AppSettings`; read through
    /// `.hoursSecondaryText` and `.hoursHairlineStyle`.
    var highContrast: Bool {
        get { self[HighContrastKey.self] }
        set { self[HighContrastKey.self] = newValue }
    }
}

/// Secondary text that follows High contrast: `.secondary` normally, the
/// primary colour at 85% with High contrast on. Use it as
/// `.foregroundStyle(.hoursSecondaryText)` wherever a screen would write
/// `.secondary`.
struct HoursSecondaryTextStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.highContrast ? Color.primary.opacity(0.85) : Color.secondary
    }
}

/// A hairline that follows High contrast: the system separator normally, a
/// darker line with High contrast on.
struct HoursHairlineStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.highContrast ? Color.primary.opacity(0.45) : Color(uiColor: .separator)
    }
}

extension ShapeStyle where Self == HoursSecondaryTextStyle {
    /// See `HoursSecondaryTextStyle`.
    static var hoursSecondaryText: HoursSecondaryTextStyle { HoursSecondaryTextStyle() }
}

extension ShapeStyle where Self == HoursHairlineStyle {
    /// See `HoursHairlineStyle`.
    static var hoursHairlineStyle: HoursHairlineStyle { HoursHairlineStyle() }
}

extension View {
    /// Hands Appearance › On site down to every screen: called once, at the
    /// root.
    func onSiteAppearance(_ settings: AppSettings) -> some View {
        environment(\.biggerButtons, settings.biggerButtons)
            .environment(\.highContrast, settings.highContrast)
    }
}
