import SwiftUI

/// What a big button does, which decides its colour (the colour rule).
enum BigActionKind: Hashable, Sendable {
    /// The accent fill, white text: the screen's main action.
    case primary
    /// A light accent tint, accent text: an action beside the main one.
    case secondary
    /// Green fill, white text: Clock in.
    case positive
    /// A red tint, red text: Delete.
    case destructive
    /// Dark orange fill, white text: Clock out.
    case warning
}

/// The redesign's big buttons for the daily actions (Clock in and out,
/// Break, Write today, Same as usual, PDF and Excel, Save on the crew day):
/// a filled rounded rectangle, full width, bold text, at least 56pt tall,
/// 64pt with Appearance › Bigger buttons. The one main action of a screen
/// passes `isMain`, for 72pt (80pt bigger).
///
/// Use it as `.buttonStyle(.bigAction(.primary))`. Two side by side share a
/// row in an `HStack`; each takes half.
struct BigActionButtonStyle: ButtonStyle {
    var kind: BigActionKind
    var isMain: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        BigActionButtonBody(configuration: configuration, kind: kind, isMain: isMain)
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
    let isMain: Bool

    @Environment(\.biggerButtons) private var biggerButtons
    @Environment(\.highContrast) private var highContrast
    @Environment(\.isEnabled) private var isEnabled

    /// Scales with Dynamic Type, so a larger text size never squeezes the
    /// label against the edges.
    @ScaledMetric(relativeTo: .body) private var regularHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var biggerHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .title3) private var mainHeight: CGFloat = 72
    @ScaledMetric(relativeTo: .title3) private var biggerMainHeight: CGFloat = 80

    static let cornerRadius: CGFloat = 20

    private var minHeight: CGFloat {
        switch (isMain, biggerButtons) {
        case (false, false): return regularHeight
        case (false, true): return biggerHeight
        case (true, false): return mainHeight
        case (true, true): return biggerMainHeight
        }
    }

    var body: some View {
        configuration.label
            .font(isMain ? Font.title3.weight(.bold) : Font.body.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.small)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                if highContrast && isTinted {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(foreground, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    /// The light kinds, drawn as a tint with coloured text, which High
    /// contrast outlines so they still read as buttons in sunlight.
    private var isTinted: Bool {
        kind == .secondary || kind == .destructive
    }

    private var foreground: Color {
        switch kind {
        case .primary, .positive, .warning: return .white
        case .secondary: return .accentColor
        case .destructive: return .hoursMissing
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return .accentColor
        case .secondary: return Color.accentColor.opacity(highContrast ? 0.20 : 0.13)
        // Fixed darker shades rather than the bright system colours, so white
        // text on them passes 4.5:1 in Light and Dark alike.
        case .positive: return Self.positiveFill
        case .destructive: return Color.hoursMissingFill.opacity(highContrast ? 0.18 : 0.12)
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
        Button {} label: { Text(verbatim: "Clock in") }.buttonStyle(.bigAction(.positive, isMain: true))
        HStack(spacing: Metrics.medium) {
            Button {} label: { Text(verbatim: "Break") }.buttonStyle(.bigAction(.secondary))
            Button {} label: { Text(verbatim: "Clock out") }.buttonStyle(.bigAction(.warning))
        }
        Button {} label: { Text(verbatim: "Write today") }.buttonStyle(.bigAction(.primary))
        Button {} label: { Text(verbatim: "Delete") }.buttonStyle(.bigAction(.destructive))
        Button {} label: { Text(verbatim: "Disabled") }.buttonStyle(.bigAction(.primary)).disabled(true)
    }
    .padding()
    .environment(\.biggerButtons, true)
}
