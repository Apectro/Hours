import SwiftUI

/// Small pieces the crew's day screens share (1.2 redesign, mockups 06–08):
/// the rounded groups of rows, the caption above a group, the status dot,
/// the four-way choice buttons and how a time range is written.

/// A white rounded group of rows, as the mockups draw "Field allowance /
/// Van kilometres / Note on the sheet". Put a `SiteDivider` between rows.
struct SiteGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, Metrics.medium + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.groupRadius, style: .continuous))
    }
}

/// The hairline between two rows of a group, following High contrast.
struct SiteDivider: View {
    var body: some View {
        Rectangle()
            .fill(.hoursHairlineStyle)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// A caption over a group, in sentence case: "Break", "Who went".
struct SiteCaption: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.hoursSecondaryText)
            .padding(.horizontal, Metrics.small)
            .padding(.top, Metrics.tiny)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row that opens something: the title, a value in grey, a chevron
/// (design v2: a plain list row; `systemImage` is no longer drawn).
struct SiteLinkRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.small) {
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.small)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .foregroundStyle(.hoursSecondaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small round mark beside a day's status: green written, orange
/// partly or not yet, red missing, grey nothing expected.
struct SiteStatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// How the four choices on a crew row are lit (mockup 06): blue for the
/// ordinary choices, orange for the ones that need a look.
enum SiteChoiceTint {
    case plain, accent, attention
}

/// One of a crew row's four buttons, or a weather chip: 44 points tall,
/// outlined, lit in the accent or in orange when chosen.
struct SiteChoiceButtonStyle: ButtonStyle {
    var tint: SiteChoiceTint
    var isCapsule = false

    func makeBody(configuration: Configuration) -> some View {
        SiteChoiceBody(configuration: configuration, tint: tint, isCapsule: isCapsule)
    }
}

private struct SiteChoiceBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: SiteChoiceTint
    let isCapsule: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline.weight(tint == .plain ? .regular : .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, isCapsule ? Metrics.medium : 2)
            .frame(maxWidth: isCapsule ? nil : .infinity, minHeight: 44)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }

    /// The chosen one in the accent, white on blue; a choice that needs a
    /// look says so in an orange word, never an orange box.
    private var foreground: Color {
        switch tint {
        case .plain: return .primary
        case .accent: return .white
        case .attention: return .hoursAttention
        }
    }

    private var fill: Color {
        tint == .accent ? .accentColor : Color(uiColor: .tertiarySystemFill)
    }
}

enum SiteDayStyle {
    static let groupRadius: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let rowHeight: CGFloat = 52

    /// "7:00 – 15:00", or a dash for a missing end.
    static func range(_ start: TimeOfDay?, _ end: TimeOfDay?, on date: CalendarDate, formatting: CalendarFormatting) -> String {
        let from = start.map { formatting.time($0, on: date) } ?? "—"
        let to = end.map { formatting.time($0, on: date) } ?? "—"
        return "\(from) – \(to)"
    }

    /// "30 min break" in hours and minutes whatever the display setting, as
    /// the site's chips write it ("0:30 break" reads like a time of day);
    /// "No break" for none.
    static func breakText(_ minutes: Int) -> String {
        guard minutes > 0 else { return String(localized: "No break") }
        let length = DurationFormatting(style: .hoursAndMinutes).string(minutes)
        return String(localized: "\(length) break", comment: "A site's usual break; the value is a duration such as 30m")
    }

    /// "4 people · 32h 30m", or "5 people · 4h each" when everyone has the same.
    static func figures(_ figures: SiteCrewFigures, durations: DurationFormatting, prefersEach: Bool = false) -> String {
        let people = String(inflected: "^[\(figures.people) person](inflect: true)")
        if prefersEach, let each = figures.eachMinutes {
            return "\(people) · \(eachText(each, durations: durations))"
        }
        return "\(people) · \(durations.string(figures.totalMinutes))"
    }

    /// "4h each".
    static func eachText(_ minutes: Int, durations: DurationFormatting) -> String {
        String(localized: "\(durations.string(minutes)) each", comment: "Hours every one of the crew gets; the value is a duration")
    }

    /// The key a crew row's identifiers end in: "you", or the name.
    static func key(_ person: PersonReference) -> String {
        person.id == CrewMember.youID ? "you" : person.name
    }
}

/// Initials in a tinted circle, as on the crew's rows (mockup 06).
struct SiteInitials: View {
    let person: PersonReference
    var isHere = true

    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(isHere ? Color.accentColor.opacity(0.13) : Color.hoursSubdued.opacity(0.2))
            if person.id == CrewMember.youID {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
            } else {
                Text(verbatim: Self.initials(of: person.name))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// Up to two letters, from the first two words of the name.
    static func initials(of name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { word in word.first.map { String($0) } }
            .joined()
            .uppercased()
    }
}

/// A row of the crew list: who, and the name to show.
struct PersonReference: Identifiable, Hashable {
    let id: UUID
    let name: String
}
