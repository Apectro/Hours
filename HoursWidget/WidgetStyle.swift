import SwiftUI
import WidgetKit

/// The widget's own small copy of the app's visual language.
///
/// Deliberately duplicated rather than shared: the app's design system imports
/// UIKit and carries settings screens' worth of styling an extension has no use
/// for. These four values are the ones a widget actually needs, and keeping
/// them here means the extension compiles the engine and nothing else.
enum WidgetPalette {
    static let positive = Color.green
    /// Under your hours is a state to notice, not an error — orange, not red.
    static let negative = Color.orange
    static let running = Color.blue

    static func balance(_ minutes: Int) -> Color {
        if minutes > 0 { return positive }
        if minutes < 0 { return negative }
        return .secondary
    }
}

extension Font {
    static func widgetFigure(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

/// A ring showing progress towards the day's expected hours.
///
/// Capped at a full circle: a fourteen-hour day should read as "well over",
/// not wrap around and look like two hours.
struct ProgressRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A flat bar, for the places a ring would not fit.
struct ProgressBar: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.2))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// What every widget shows when there is nothing to show.
///
/// Two different nothings, and they need different words: one is waiting for
/// the app to be opened, the other cannot ever work until a capability is
/// turned on. Telling someone to "open the app" when opening it will not help
/// is worse than saying nothing.
struct EmptyStateView: View {
    var state: HoursEntry.State
    var compact: Bool = false

    private var symbol: String {
        switch state {
        case .unavailable: return "exclamationmark.triangle"
        case .locked: return "lock.fill"
        default: return "clock.badge.questionmark"
        }
    }

    // Built as `String`, so unlike a `Text("literal")` these do not localise
    // themselves — they have to ask.
    private var message: String {
        switch state {
        case .unavailable:
            return compact
                ? String(localized: "Set up")
                : String(localized: "Turn on App Groups to use the widget")
        case .waiting:
            return compact
                ? String(localized: "Open Hours")
                : String(localized: "Open Hours once to fill this in")
        case .locked:
            return compact
                ? String(localized: "Hours Pro")
                : String(localized: "Widgets are part of Hours Pro")
        case .data, .sample:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

extension View {
    /// Home Screen widgets need a background; Lock Screen accessories are drawn
    /// onto the wallpaper and must not have one. Both still have to declare a
    /// container background, which is what iOS 17 made mandatory.
    @ViewBuilder
    func widgetBackground(onHomeScreen: Bool) -> some View {
        if onHomeScreen {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            containerBackground(.clear, for: .widget)
        }
    }
}
