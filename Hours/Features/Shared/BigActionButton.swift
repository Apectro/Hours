import SwiftUI

/// What a big button does, which decides its colour (the colour rule).
enum BigActionKind: Hashable, Sendable {
    /// The accent fill, white text: the screen's one main action.
    case primary
    /// The system's tertiary fill, primary text: an action beside the main
    /// one (Break, Previous day).
    case secondary
    /// Green fill, white text: Clock in only.
    case positive
    /// The tertiary fill, red text: Delete, Clear this day.
    case destructive
    /// Dark orange fill, white text. Kept so older call sites compile; new
    /// screens use `.primary` (Clock out is the main action while working).
    case warning
}

/// The big buttons for the daily actions (Clock in and out, Break, Write
/// today, Edit, Same as usual, PDF and Excel, Save on the crew day), in the
/// look of Apple's own apps: a capsule, full width, 17pt semibold, 52pt tall
/// (60pt with Appearance › Bigger buttons). One primary per screen, at the
/// bottom.
///
/// Use it as `.buttonStyle(.bigAction(.primary))`. Two side by side share a
/// row in an `HStack`; each takes half. `isMain` is kept for the callers
/// that pass it; every big button is the same height now.
struct BigActionButtonStyle: ButtonStyle {
    var kind: BigActionKind
    var isMain: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        BigActionButtonBody(configuration: configuration, kind: kind)
    }
}

extension ButtonStyle where Self == BigActionButtonStyle {
    /// See `BigActionButtonStyle`.
    static func bigAction(_ kind: BigActionKind, isMain: Bool = false) -> BigActionButtonStyle {
        BigActionButtonStyle(kind: kind, isMain: isMain)
    }
}

/// A view rather than the style's body, so it can read the environment.
private struct BigActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: BigActionKind

    @Environment(\.biggerButtons) private var biggerButtons
    @Environment(\.highContrast) private var highContrast
    @Environment(\.isEnabled) private var isEnabled

    /// Scales with Dynamic Type, so a larger text size never squeezes the
    /// label against the edges.
    @ScaledMetric(relativeTo: .body) private var regularHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var biggerHeight: CGFloat = 60

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.small)
            .frame(maxWidth: .infinity, minHeight: biggerButtons ? biggerHeight : regularHeight)
            .background(fill, in: Capsule())
            .overlay {
                // High contrast: the grey kinds get an outline, so they
                // still read as buttons in sunlight.
                if highContrast && isGrey {
                    Capsule().strokeBorder(.hoursHairlineStyle, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var isGrey: Bool {
        kind == .secondary || kind == .destructive
    }

    private var foreground: Color {
        switch kind {
        case .primary, .positive, .warning: return .white
        case .secondary: return .primary
        case .destructive: return .hoursMissing
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return .accentColor
        case .secondary, .destructive: return Color(uiColor: .tertiarySystemFill)
        // Fixed darker shades rather than the bright system colours, so white
        // text on them passes 4.5:1 in Light and Dark alike.
        case .positive: return Self.positiveFill
        case .warning: return Self.warningFill
        }
    }

    /// #1F7A45, about 5.4:1 with white.
    private static let positiveFill = Color(red: 0x1F / 255, green: 0x7A / 255, blue: 0x45 / 255)
    /// #C2410C, about 5.2:1 with white.
    private static let warningFill = Color(red: 0xC2 / 255, green: 0x41 / 255, blue: 0x0C / 255)
}

#Preview {
    VStack(spacing: Metrics.medium) {
        Button {} label: { Text(verbatim: "Clock in") }.buttonStyle(.bigAction(.positive))
        HStack(spacing: Metrics.medium) {
            Button {} label: { Text(verbatim: "Break") }.buttonStyle(.bigAction(.secondary))
            Button {} label: { Text(verbatim: "Clock out") }.buttonStyle(.bigAction(.primary))
        }
        Button {} label: { Text(verbatim: "Clear this day") }.buttonStyle(.bigAction(.destructive))
        Button {} label: { Text(verbatim: "Disabled") }.buttonStyle(.bigAction(.primary)).disabled(true)
    }
    .padding()
    .environment(\.biggerButtons, true)
}
