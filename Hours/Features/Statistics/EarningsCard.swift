import SwiftUI

/// What a period earned, and where it came from.
///
/// Beside the hours cards rather than instead of them: the hours are what
/// the money is made of, and what a timesheet is checked against.
struct EarningsCard: View {
    let earnings: EarningsSummary
    let money: MoneyFormatting
    let formatting: CalendarFormatting
    /// A list of months, for a year.
    var showsMonths = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                StatTile(label: String(localized: "Earned"), value: money.string(earnings.totalCents))
                    .accessibilityIdentifier("insights-earned")

                let parts = earnings.breakdown
                MetricRow(label: String(localized: "Hours worked"), value: money.string(parts.baseCents), systemImage: "clock")
                if parts.overtimeCents > 0 {
                    MetricRow(label: String(localized: "Overtime surcharge"), value: money.string(parts.overtimeCents), systemImage: "arrow.up.right")
                }
                if parts.saturdayCents > 0 {
                    MetricRow(label: String(localized: "Saturday"), value: money.string(parts.saturdayCents), systemImage: "calendar")
                }
                if parts.sundayAndHolidayCents > 0 {
                    MetricRow(label: String(localized: "Sunday and public holidays"), value: money.string(parts.sundayAndHolidayCents), systemImage: "sun.max")
                }
                if parts.nightCents > 0 {
                    MetricRow(label: String(localized: "Night"), value: money.string(parts.nightCents), systemImage: "moon")
                }
                if parts.paidAbsenceCents > 0 {
                    MetricRow(label: String(localized: "Paid days off"), value: money.string(parts.paidAbsenceCents), systemImage: "checkmark.seal")
                }

                if showsMonths && earnings.months.count > 1 {
                    Divider()
                    Text("Month by month")
                        .font(.subheadline.weight(.semibold))
                    ForEach(earnings.months) { month in
                        HStack {
                            Text(formatting.monthTitle(month.month))
                                .font(.subheadline)
                            Spacer(minLength: Metrics.small)
                            Text(money.string(month.totalCents))
                                .font(.hoursFigure(.subheadline, weight: .medium))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Where Insights would show earnings, while no rate is set: one line that
/// leads to where it is.
struct EarningsHint: View {
    let jobID: UUID

    var body: some View {
        NavigationLink {
            PaySettingsScreen(jobID: jobID)
        } label: {
            SurfaceCard {
                HStack(spacing: Metrics.medium) {
                    Image(systemName: "banknote")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Set your hourly rate")
                            .font(.subheadline.weight(.semibold))
                        Text("See what your hours earn, overtime and surcharges included.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("insights-set-rate")
    }
}
