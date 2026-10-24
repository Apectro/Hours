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
    /// Field allowance, kilometres and travel, each a line of its own under
    /// the pay — never mixed into it — only when there is some.
    var allowance: AllowanceSummary? = nil

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
                if let allowance, !allowance.isEmpty {
                    AllowanceLines(allowance: allowance, money: money)
                }
                if let reducedNote {
                    Text(verbatim: reducedNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

extension EarningsCard {
    /// "Paid days off at 70% · 3 days paid by health insurance": small,
    /// and only when some paid absence paid less than in full.
    var reducedNote: String? {
        var parts: [String] = []
        let percents = earnings.reducedAbsencePercents
        if !percents.isEmpty {
            let shares = percents.map { "\($0)%" }.joined(separator: ", ")
            parts.append(String(
                localized: "Paid days off at \(shares)",
                comment: "Insights, under the money; the value is like 70%"
            ))
        }
        let insured = earnings.healthInsuranceDays
        if insured > 0 {
            // Sick days past the employer's first 42; Croatian names HZZO.
            parts.append(String(inflected: "^[\(insured) day](inflect: true) paid by health insurance"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The field allowance, the kilometres and travel time as Insights lines:
/// days or kilometres with what they come to at the rates in settings, and
/// travel as a time. Each only when there is some.
struct AllowanceLines: View {
    let allowance: AllowanceSummary
    let money: MoneyFormatting

    var body: some View {
        VStack(spacing: Metrics.medium) {
            if allowance.allowanceDays > 0 {
                MetricRow(
                    label: String(inflected: "Field allowance · ^[\(allowance.allowanceDays) day](inflect: true)"),
                    value: amount(allowance.allowanceCents),
                    systemImage: "suitcase"
                )
                .accessibilityIdentifier("insights-allowance")
            }
            if allowance.kilometres > 0 {
                MetricRow(
                    label: String(
                        localized: "Kilometres · \(allowance.kilometres) km",
                        comment: "Insights, the month's kilometres; the value is a number"
                    ),
                    value: amount(allowance.mileageCents),
                    systemImage: "car"
                )
                .accessibilityIdentifier("insights-kilometres")
            }
            if allowance.travelMinutes > 0 {
                MetricRow(
                    label: String(localized: "Travel time"),
                    value: DurationFormatting(style: .clock).string(allowance.travelMinutes),
                    systemImage: "road.lanes"
                )
            }
        }
    }

    /// What it came to; nothing while no rate is set, rather than a zero.
    private func amount(_ cents: Int) -> String {
        cents > 0 ? money.string(cents) : String()
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
