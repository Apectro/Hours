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
    /// The period's worked hours by site and own (2026-11-24): "Sites 112h
    /// · Own 16h 30m" under Worked. Nil while there is no site, when all
    /// hours are your own and there is nothing to tell apart.
    var sources: PeriodSources? = nil
    /// The chip chosen above the month. Anything but All makes this the
    /// totals of that source alone: its worked hours, named, and none of
    /// the figures that belong to the whole period.
    var filter: SourceFilter = .all
    /// The chosen source by name; nil for All.
    var filterName: String? = nil

    private var formatting: DurationFormatting { settings.displayFormatting }

    var body: some View {
        Section {
            workedRow
                .tourTarget(.calendarSummary)
                .id(CalendarScreen.summaryAnchor)
            if !isFiltered {
                wholePeriodRows
            }
        } header: {
            if !title.isEmpty {
                Text(verbatim: title)
                    .textCase(nil)
            }
        } footer: {
            if isFiltered {
                Text("Only these hours. Choose All above the month for the month's totals.")
                    .accessibilityIdentifier("calendar-summary-filtered")
            } else {
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
    }

    /// A chip other than All is chosen, and the hours are told apart.
    private var isFiltered: Bool { sources != nil && filter != .all }

    /// Worked, and under it where the hours came from: "Sites 112h · Own
    /// 16h 30m", or the chosen source's name. A plain stack rather than
    /// `LabeledContent`, so the line and the figure are each found by
    /// their identifier.
    @ViewBuilder
    private var workedRow: some View {
        if sources == nil {
            // No site: the row as it always was.
            row("Worked", formatting.string(summary.workedMinutes))
        } else {
            sourcedWorkedRow
        }
    }

    private var sourcedWorkedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Worked")
                if let sourcesLine {
                    Text(verbatim: sourcesLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                        .accessibilityIdentifier("calendar-summary-sources")
                }
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: formatting.string(workedMinutes))
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityIdentifier("calendar-summary-worked")
        }
    }

    /// The period's worked hours, or the chosen source's.
    private var workedMinutes: Int {
        guard let sources, filter != .all else { return summary.workedMinutes }
        return sources.minutes(for: filter)
    }

    /// "Sites 112h · Own 16h 30m" for All; the source's name under a chip;
    /// nothing without sites.
    private var sourcesLine: String? {
        guard let sources else { return nil }
        if filter != .all { return filterName }
        return String(
            localized: "Sites \(formatting.string(sources.siteMinutes)) · Own \(formatting.string(sources.ownMinutes))",
            comment: "Calendar totals, under Worked: hours on sites and hours of your own, e.g. Sites 112h · Own 16h 30m"
        )
    }

    /// Everything that is the whole period's, and so not shown under a chip.
    @ViewBuilder
    private var wholePeriodRows: some View {
        if settings.features.trackExpectedHours {
            row("Expected", formatting.string(summary.expectedMinutes))
        }
        if let earnings {
            row("Earned", settings.money.string(earnings.totalCents, showsCents: false, hidden: settings.hideAmounts))
                .accessibilityIdentifier("calendar-summary-earned")
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
