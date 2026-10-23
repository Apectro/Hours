import SwiftUI

/// ‹ October 2026 › with what the period holds underneath.
///
/// One stepper for every period the app pages through, so they all look and
/// behave the same: 44-point arrows either side, the title and a caption in
/// the middle, and the forward arrow off once the next period has not begun.
/// Export uses it for a site's month and for your own range; the other
/// steppers (Insights, the site grid) can adopt it as they are touched.
struct PeriodStepper: View {
    let title: String
    /// "21 days · 5 people", or nothing while the period is being read.
    let caption: String
    let previousLabel: LocalizedStringKey
    let nextLabel: LocalizedStringKey
    let canGoForward: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            stepButton(systemImage: "chevron.left", label: previousLabel, action: onPrevious)
                .accessibilityIdentifier("period-previous")
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
            stepButton(systemImage: "chevron.right", label: nextLabel, action: onNext)
                .disabled(!canGoForward)
                .accessibilityIdentifier("period-next")
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

extension PeriodStepper {
    /// A month at a time, for a site's sheet: always one month, because that
    /// is what the boss asks for.
    init(month: Binding<YearMonth>, latest: YearMonth, title: String, caption: String) {
        self.init(
            title: title,
            caption: caption,
            previousLabel: "Previous month",
            nextLabel: "Next month",
            canGoForward: month.wrappedValue < latest,
            onPrevious: { month.wrappedValue = month.wrappedValue.adding(months: -1) },
            onNext: { month.wrappedValue = month.wrappedValue.adding(months: 1) }
        )
    }
}
