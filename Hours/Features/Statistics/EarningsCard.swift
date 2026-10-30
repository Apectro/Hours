import SwiftUI

/// What a period earned, and where it came from: a list section headed
/// by the total (design v2: rows, no card).
///
/// Beside the hours rather than instead of them: the hours are what the
/// money is made of, and what a timesheet is checked against.
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
        Section {
            InsightsRow(title: String(localized: "Earned")) {
                Text(money.string(earnings.totalCents))
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("insights-earned")

            let parts = earnings.breakdown
            InsightsRow(title: String(localized: "Hours worked"), value: money.string(parts.baseCents))
            if parts.overtimeCents > 0 {
                InsightsRow(title: String(localized: "Overtime surcharge"), value: money.string(parts.overtimeCents))
            }
            if parts.saturdayCents > 0 {
                InsightsRow(title: String(localized: "Saturday"), value: money.string(parts.saturdayCents))
            }
            if parts.sundayAndHolidayCents > 0 {
                InsightsRow(title: String(localized: "Sunday and public holidays"), value: money.string(parts.sundayAndHolidayCents))
            }
            if parts.nightCents > 0 {
                InsightsRow(title: String(localized: "Night"), value: money.string(parts.nightCents))
            }
            if parts.paidAbsenceCents > 0 {
                InsightsRow(title: String(localized: "Paid days off"), value: money.string(parts.paidAbsenceCents))
            }
            if let allowance, !allowance.isEmpty {
                AllowanceLines(allowance: allowance, money: money)
            }
            if showsMonths && earnings.months.count > 1 {
                ForEach(earnings.months) { month in
                    InsightsRow(title: formatting.monthTitle(month.month), value: money.string(month.totalCents))
                }
            }
        } header: {
            Text("Pay")
        } footer: {
            if let reducedNote {
                Text(verbatim: reducedNote)
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

/// The field allowance, the kilometres and travel time as Insights rows:
/// days or kilometres with what they come to at the rates in settings, and
/// travel as a time. Each only when there is some. Rows of the section it
/// is put in.
struct AllowanceLines: View {
    let allowance: AllowanceSummary
    let money: MoneyFormatting

    var body: some View {
        if allowance.allowanceDays > 0 {
            InsightsRow(
                title: String(inflected: "Field allowance · ^[\(allowance.allowanceDays) day](inflect: true)"),
                value: amount(allowance.allowanceCents)
            )
            .accessibilityIdentifier("insights-allowance")
        }
        if allowance.kilometres > 0 {
            InsightsRow(
                title: String(
                    localized: "Kilometres · \(allowance.kilometres) km",
                    comment: "Insights, the month's kilometres; the value is a number"
                ),
                value: amount(allowance.mileageCents)
            )
            .accessibilityIdentifier("insights-kilometres")
        }
        if allowance.travelMinutes > 0 {
            InsightsRow(
                title: String(localized: "Travel time"),
                value: DurationFormatting(style: .clock).string(allowance.travelMinutes)
            )
        }
    }

    /// What it came to; nothing while no rate is set, rather than a zero.
    private func amount(_ cents: Int) -> String {
        cents > 0 ? money.string(cents) : String()
    }
}

/// Where Insights would show earnings, while no rate is set: one row that
/// leads to where it is, and one sentence under it.
struct EarningsHint: View {
    let jobID: UUID

    var body: some View {
        Section {
            NavigationLink {
                PaySettingsScreen(jobID: jobID)
            } label: {
                Text("Set your hourly rate")
            }
            .accessibilityIdentifier("insights-set-rate")
        } footer: {
            Text("See what your hours earn, overtime and surcharges included.")
        }
    }
}
