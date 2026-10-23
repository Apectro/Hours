import SwiftUI

/// The header of a section that opens in place: its title, a one-line grey
/// summary of what is inside while it is closed ("Rain, 8 °C", "Items: 3"),
/// and a chevron that turns as it opens. The whole row is one button, full
/// width and at least 44 points tall.
///
/// The caller animates the change and puts the accessibility identifier on
/// this header — on the button itself, never on a container around it, so
/// an identifier set further out cannot replace it (see the report screen's
/// share bar for how that goes wrong).
struct DisclosureHeader: View {
    let title: String
    /// Shown under the title while the section is closed; nothing when empty.
    let summary: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if showsSummary {
                        Text(verbatim: summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: showsSummary ? "\(title), \(summary)" : title))
        // A button, not also a header: UI tests and VoiceOver find it as
        // the button it is, and its value says whether it is open.
        .accessibilityValue(Text(stateWord))
    }

    private var showsSummary: Bool { !isExpanded && !summary.isEmpty }

    private var stateWord: LocalizedStringKey {
        if isExpanded { return "Expanded" }
        return "Collapsed"
    }
}
