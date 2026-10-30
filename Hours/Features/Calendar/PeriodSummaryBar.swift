import SwiftUI

/// The period's totals under the calendar (design v2): a section of plain
/// rows, a noun on the left and the figure in grey on the right — Worked,
/// Expected, the balance or what was earned, the average day — and the
/// day counts and the allowance as its footer.
struct PeriodSummaryBar: View {
    let summary: PeriodSummary
    let settings: AppSettings
    let catalog: DayTypeCatalog
    /// "October", or the week: the section's header.
    var title: String = ""
    /// When set, what was earned is shown beside the balance.
    var earnings: EarningsSummary? = nil
    /// Field allowance, kilometres and travel: a quiet line of their own,
    /// only when there is any.
    var allowance: AllowanceSummary? = nil

    private var formatting: DurationFormatting { settings.displayFormatting }

    var body: some View {
        Section {
            row("Worked", formatting.string(summary.workedMinutes))
                .tourTarget(.calendarSummary)
                .id(CalendarScreen.summaryAnchor)
            if settings.features.trackExpectedHours {
                row("Expected", formatting.string(summary.expectedMinutes))
            }
            if let earnings {
                row("Earned", settings.money.string(earnings.totalCents, showsCents: false))
            }
            if settings.features.showsBalance {
                LabeledContent {
                    Text(verbatim: formatting.signedString(summary.balanceMinutes))
                        .monospacedDigit()
                        .foregroundStyle(Color.hoursBalance(summary.balanceMinutes))
                } label: {
                    Text("Balance")
                    if let balanceCaption {
                        Text(verbatim: balanceCaption)
                            .monospacedDigit()
                    }
                }
            }
            if summary.daysWorked > 0 {
                LabeledContent {
                    Text(verbatim: formatting.string(summary.averageWorkedMinutesPerWorkedDay))
                        .monospacedDigit()
                } label: {
                    Text("Average")
                    Text("per day worked")
                }
            }
        } header: {
            if !title.isEmpty {
                Text(verbatim: title)
                    .textCase(nil)
            }
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                if !countsLine.isEmpty {
                    Text(countsLine)
                }
                if !allowanceLine.isEmpty {
                    Text(allowanceLine)
                        .accessibilityIdentifier("calendar-summary-allowance")
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
        } label: {
            Text(label)
        }
    }

    private var balanceCaption: String? {
        guard summary.overtimeMinutes > 0, summary.deficitMinutes > 0 else { return nil }
        // Only worth showing when the net hides movement in both directions.
        return "+\(formatting.string(summary.overtimeMinutes)) / \(formatting.string(-summary.deficitMinutes))"
    }

    /// "Field allowance · 12 days  ·  340 km  ·  Travel 6:30", each part only
    /// when there is some.
    private var allowanceLine: String {
        guard let allowance, !allowance.isEmpty else { return "" }
        var parts: [String] = []
        if allowance.allowanceDays > 0 {
            parts.append(String(inflected: "Field allowance · ^[\(allowance.allowanceDays) day](inflect: true)"))
        }
        if allowance.kilometres > 0 {
            parts.append(String(
                localized: "\(allowance.kilometres) km",
                comment: "A distance driven; the value is a number of kilometres"
            ))
        }
        if allowance.travelMinutes > 0 {
            parts.append(String(
                localized: "Travel \(DurationFormatting(style: .clock).string(allowance.travelMinutes))",
                comment: "Travel time in the month's totals; the value is like 6:30"
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var countsLine: String {
        var parts: [String] = []
        // Inflected rather than a hand-picked noun: "1 day"/"2 days" is the
        // easy half, and the pattern is what a translator needs for languages
        // where the number itself changes the word.
        parts.append(String(inflected: "^[\(summary.daysWorked) day](inflect: true) worked"))
        if summary.scheduledWorkingDays > 0 {
            parts.append(String(localized: "\(summary.scheduledWorkingDays) scheduled"))
        }
        for definition in catalog.all where definition.expectation == .creditedAbsence {
            let count = summary.count(of: definition.id)
            if count > 0 { parts.append("\(count) \(definition.nameInRunningText())") }
        }
        if summary.daysOff > 0 { parts.append(String(localized: "\(summary.daysOff) off")) }
        return parts.joined(separator: " · ")
    }
}
