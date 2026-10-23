import SwiftUI

/// The totals strip under the calendar.
///
/// Three figures at full size and a quiet counts line beneath. Anything more
/// competes with the grid for attention and the grid should win.
struct PeriodSummaryBar: View {
    let summary: PeriodSummary
    let settings: AppSettings
    let catalog: DayTypeCatalog
    /// When set, what was earned takes the balance's place.
    var earnings: EarningsSummary? = nil
    /// Sends these figures: Export, opened on this period.
    var onExport: (() -> Void)? = nil

    private var formatting: DurationFormatting { settings.displayFormatting }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(
                    label: String(localized: "Worked"),
                    value: formatting.string(summary.workedMinutes),
                    caption: settings.features.trackExpectedHours
                        ? "of \(formatting.string(summary.expectedMinutes))"
                        : nil
                )

                if let earnings {
                    Divider()
                    StatTile(
                        label: String(localized: "Earned"),
                        value: settings.money.string(earnings.totalCents, showsCents: false),
                        caption: earnedCaption
                    )
                } else if settings.features.showsBalance {
                    Divider()
                    StatTile(
                        label: String(localized: "Balance"),
                        value: formatting.signedString(summary.balanceMinutes),
                        caption: balanceCaption,
                        tint: Color.hoursBalance(summary.balanceMinutes)
                    )
                }

                Divider()
                StatTile(
                    label: String(localized: "Average"),
                    value: formatting.string(summary.averageWorkedMinutesPerWorkedDay),
                    caption: String(localized: "per day worked")
                )
            }
            // The dividers run the height of the tallest tile, at any text
            // size, instead of a fixed 34 points that looked broken at the
            // accessibility sizes.
            .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: Metrics.small) {
                if !countsLine.isEmpty {
                    Text(countsLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let onExport {
                    Button(action: onExport) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("calendar-summary-export")
                }
            }
        }
    }

    /// The balance, small, under the money, for someone who still wants it
    /// at a glance.
    private var earnedCaption: String? {
        guard settings.features.showsBalance else { return nil }
        return String(
            localized: "balance \(formatting.signedString(summary.balanceMinutes))",
            comment: "Under the month's earnings; the value is the hours balance"
        )
    }

    private var balanceCaption: String? {
        guard summary.overtimeMinutes > 0, summary.deficitMinutes > 0 else { return nil }
        // Only worth showing when the net hides movement in both directions.
        return "+\(formatting.string(summary.overtimeMinutes)) / \(formatting.string(-summary.deficitMinutes))"
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
        return parts.joined(separator: "  ·  ")
    }
}
