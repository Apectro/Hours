import SwiftUI
import WidgetKit

/// The widgets' colours, taken from the app icon: a navy night and an amber
/// hard hat.
///
/// Deliberately duplicated rather than shared: the app's design system imports
/// UIKit and carries settings screens' worth of styling an extension has no use
/// for, and the widgets now have a look of their own besides.
enum WidgetPalette {
    static let navy = Color(red: 0x12 / 255, green: 0x1a / 255, blue: 0x45 / 255)
    static let navyLight = Color(red: 0x1f / 255, green: 0x2d / 255, blue: 0x6b / 255)
    static let amber = Color(red: 0xff / 255, green: 0xb0 / 255, blue: 0x2e / 255)
    static let amberLight = Color(red: 0xff / 255, green: 0xbf / 255, blue: 0x47 / 255)
    static let amberDeep = Color(red: 0xf0 / 255, green: 0x8a / 255, blue: 0x1e / 255)
    /// Secondary text on navy.
    static let mist = Color(red: 0x9f / 255, green: 0xb0 / 255, blue: 0xe8 / 255)
    static let running = Color(red: 0x34 / 255, green: 0xc7 / 255, blue: 0x59 / 255)
    static let positive = Color(red: 0x4c / 255, green: 0xd9 / 255, blue: 0x64 / 255)
    /// The site card's paper.
    static let paper = Color(red: 0xf6 / 255, green: 0xf3 / 255, blue: 0xee / 255)
    static let paperButton = Color(red: 0xe9 / 255, green: 0xe4 / 255, blue: 0xdc / 255)
    static let paperText = Color(red: 0x6b / 255, green: 0x6b / 255, blue: 0x72 / 255)
    static let pendingBackground = Color(red: 0xff / 255, green: 0xf0 / 255, blue: 0xd6 / 255)
    static let pendingText = Color(red: 0xc5 / 255, green: 0x5a / 255, blue: 0x00 / 255)
    static let writtenText = Color(red: 0x1f / 255, green: 0x7a / 255, blue: 0x3a / 255)
    static let stop = Color(red: 0xff / 255, green: 0x45 / 255, blue: 0x3a / 255)

    /// One colour per face on the site card, in turn.
    static let faces: [Color] = [
        Color(red: 0x2c / 255, green: 0x4a / 255, blue: 0xa8 / 255),
        Color(red: 0xe0 / 255, green: 0x7b / 255, blue: 0x12 / 255),
        Color(red: 0x4f / 255, green: 0x7d / 255, blue: 0x5a / 255),
        navyLight,
    ]

    /// Over your hours is green; under them is amber rather than red, because
    /// it is a state to notice, not an error.
    static func balance(_ minutes: Int) -> Color {
        if minutes > 0 { return positive }
        if minutes < 0 { return amber }
        return mist
    }
}

extension Font {
    static func widgetFigure(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    /// A figure at a size the design fixes, for the Home Screen where the
    /// widget's own size is fixed too. Lock Screen text uses text styles
    /// instead, so it follows Dynamic Type.
    static func widgetFigure(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// The three cards the widgets are drawn on.
enum WidgetCard {
    case navy
    case amber
    case paper

    var background: LinearGradient {
        switch self {
        case .navy:
            return LinearGradient(
                colors: [WidgetPalette.navyLight, WidgetPalette.navy],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .amber:
            return LinearGradient(
                colors: [WidgetPalette.amberLight, WidgetPalette.amberDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .paper:
            return LinearGradient(colors: [WidgetPalette.paper], startPoint: .top, endPoint: .bottom)
        }
    }

    /// The card's colours are the same in dark mode and light, so the text on
    /// it follows the card rather than the phone: `.secondary` on navy has to
    /// be light whatever the system appearance is.
    var colorScheme: ColorScheme {
        self == .navy ? .dark : .light
    }
}

extension View {
    /// Home Screen widgets get their card; Lock Screen accessories are drawn
    /// onto the wallpaper and must not have one. Both still declare a
    /// container background, which iOS 17 made mandatory.
    ///
    /// In the tinted and clear Home Screen styles the system removes the
    /// background itself, so the content has to read without it; see
    /// `isFullColor` at each place that fills a shape.
    @ViewBuilder
    func widgetCard(_ card: WidgetCard, onHomeScreen: Bool) -> some View {
        if onHomeScreen {
            environment(\.colorScheme, card.colorScheme)
                .containerBackground(card.background, for: .widget)
        } else {
            containerBackground(.clear, for: .widget)
        }
    }
}

extension WidgetRenderingMode {
    /// False in the tinted and clear Home Screen styles and on the Lock
    /// Screen, where every colour becomes one tint and a filled shape behind
    /// text turns both into a single blob.
    var isFullColor: Bool { self == .fullColor }
}

/// The app icon's mark: a hard hat, as a half-disc on a short brim.
struct HardHat: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let brim = rect.height * 0.24
        let radius = min(rect.width * 0.38, rect.height - brim)
        let base = CGPoint(x: rect.midX, y: rect.maxY - brim)

        path.move(to: CGPoint(x: base.x - radius, y: base.y))
        // From the left round over the top to the right: in SwiftUI's
        // downward y, increasing angles run clockwise on screen.
        path.addArc(center: base, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.maxY - brim, width: rect.width, height: brim),
            cornerSize: CGSize(width: brim / 2, height: brim / 2)
        )
        return path
    }
}

/// The hard hat on an amber tile, as the app icon draws it.
struct HardHatBadge: View {
    var size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(WidgetPalette.amber.opacity(renderingMode.isFullColor ? 1 : 0.3))
            HardHat()
                .fill(renderingMode.isFullColor ? WidgetPalette.navy : Color.primary)
                .frame(width: size * 0.56, height: size * 0.32)
        }
        .frame(width: size, height: size)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// A ring showing progress towards the expected hours.
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
                .widgetAccentable()
        }
    }
}

/// A small rounded label: the balance on the week widget, the day's state on
/// the site widget.
struct WidgetChip: View {
    var text: String
    var foreground: Color
    var background: Color
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(
                renderingMode.isFullColor ? background : Color.primary.opacity(0.15),
                in: Capsule()
            )
    }
}

/// The small upper-case heading each card starts with.
///
/// Takes a `Text` rather than a key, because one heading is a month name the
/// phone has already put into its own language and must not be looked up.
struct WidgetHeading: View {
    var text: Text
    var color: Color

    var body: some View {
        text
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(color)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// What every widget shows when there is nothing to show.
///
/// Different nothings need different words: one is waiting for the app to be
/// opened, one cannot ever work until a capability is turned on, and one is
/// simply not part of what was bought. Telling someone to "open the app" when
/// opening it will not help is worse than saying nothing.
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
                ? String(localized: "Open Zeitkonto")
                : String(localized: "Open Zeitkonto once to fill this in")
        case .locked:
            return compact
                ? String(localized: "Zeitkonto Pro")
                : String(localized: "Widgets are part of Zeitkonto Pro")
        case .data, .sample:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if compact {
                Image(systemName: symbol)
                    .font(.title3)
            } else {
                HardHatBadge(size: 30)
            }
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

extension HoursEntry {
    /// Real figures or the gallery's sample: the two states with something to
    /// draw.
    var hasData: Bool { state == .data || state == .sample }
}

extension WidgetSnapshot {
    /// What the running clock is for: its site when that is certain, its job
    /// when there is more than one, otherwise nothing.
    var clockPlace: String? { clockSiteName ?? clockJobName }
}
