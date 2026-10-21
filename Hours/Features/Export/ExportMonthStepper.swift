import SwiftUI

/// ‹ October 2026 › with what the month holds underneath, for a site's sheet.
///
/// A site's sheet is always one month — it is what the director asks for —
/// so it gets a stepper rather than the timesheet's choice of ranges.
struct ExportMonthStepper: View {
    @Binding var month: YearMonth
    /// The latest month that can be chosen: nothing has been worked after it.
    let latest: YearMonth
    let title: String
    /// "21 days · 5 people", or nothing while the month is being read.
    let caption: String

    var body: some View {
        HStack {
            stepButton(systemImage: "chevron.left", label: "Previous month") {
                month = month.adding(months: -1)
            }
            Spacer(minLength: Metrics.small)
            VStack(spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                if !caption.isEmpty {
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Metrics.small)
            stepButton(systemImage: "chevron.right", label: "Next month") {
                month = month.adding(months: 1)
            }
            .disabled(month >= latest)
        }
        // Two buttons in one row: without this a tap anywhere in the row
        // presses both.
        .buttonStyle(.borderless)
    }

    private func stepButton(systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }
}
