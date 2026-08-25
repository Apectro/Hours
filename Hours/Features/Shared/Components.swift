import SwiftUI

/// A single figure with its label. The building block of every summary in the
/// app; nothing else is allowed to invent its own way of showing a number.
struct StatTile: View {
    var label: String
    var value: String
    var caption: String? = nil
    var tint: Color = .primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: Metrics.tiny) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.hoursFigure(.title3))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(value)"))
    }
}

/// Label on the left, value on the right. For dense read-only detail.
struct MetricRow: View {
    var label: String
    var value: String
    var tint: Color = .primary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Metrics.small) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: Metrics.medium)
            Text(value)
                .font(.hoursFigure(.body, weight: .medium))
                .foregroundStyle(tint)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// A quiet surface for content that sits outside a `List`. Used sparingly —
/// the app leans on grouped lists, not on cards everywhere.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = Metrics.large
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

/// The coloured dot that identifies a day type at a glance.
struct DayTypeBadge: View {
    var definition: DayTypeDefinition
    var size: CGFloat = 22
    var showsLabel = false

    var body: some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: definition.symbolName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(definition.tint.color)
                .frame(width: size, height: size)
                .background(definition.tint.color.opacity(0.15), in: Circle())
            if showsLabel {
                Text(definition.name)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(definition.name)
    }
}

/// A signed duration, coloured by sign. Used for every balance in the app.
struct BalanceText: View {
    var minutes: Int
    var formatting: DurationFormatting = .display
    var font: Font = .hoursFigure(.body)

    var body: some View {
        Text(formatting.signedString(minutes))
            .font(font)
            .foregroundStyle(Color.hoursBalance(minutes))
            .contentTransition(.numericText())
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let magnitude = DurationFormatting(style: .hoursAndMinutes, minusSign: "").string(abs(minutes))
        if minutes > 0 { return "\(magnitude) over" }
        if minutes < 0 { return "\(magnitude) under" }
        return "on target"
    }
}
