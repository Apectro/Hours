import SwiftUI

/// The three formats as cards, three to a row, each saying what it is for.
struct ExportFormatCards: View {
    @Binding var selection: ExportFormat

    /// Paper first: the PDF is what most people are sending.
    private static let order: [ExportFormat] = [.pdf, .xlsx, .csv]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.small), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.small) {
            ForEach(ExportFormatCards.order) { format in
                ExportFormatCard(format: format, isSelected: format == selection) {
                    selection = format
                }
            }
        }
    }
}

private struct ExportFormatCard: View {
    let format: ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                // A product name, the same in every language.
                Text(verbatim: format.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(format.purpose)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, Metrics.small)
            .padding(.horizontal, Metrics.tiny)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.smallCornerRadius)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("export-format-\(format.rawValue)")
    }
}
