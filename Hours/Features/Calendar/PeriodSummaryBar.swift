import SwiftUI

/// The totals strip under the calendar.
///
/// Three figures at full size and a quiet counts line beneath. Anything more
/// competes with the grid for attention and the grid should win.
struct PeriodSummaryBar: View {
    let summary: PeriodSummary
    let settings: AppSettings
    let catalog: DayTypeCatalog

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

                if settings.features.showsBalance {
                    Divider().frame(height: 34)
                    StatTile(
                        label: String(localized: "Balance"),
                        value: formatting.signedString(summary.balanceMinutes),
                        caption: balanceCaption,
                        tint: Color.hoursBalance(summary.balanceMinutes)
                    )
                }

                Divider().frame(height: 34)
                StatTile(
                    label: String(localized: "Average"),
                    value: formatting.string(summary.averageWorkedMinutesPerWorkedDay),
                    caption: String(localized: "per day worked")
                )
            }

            if !countsLine.isEmpty {
                Text(countsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        parts.append(String(localized: "^[\(summary.daysWorked) day](inflect: true) worked"))
        if summary.scheduledWorkingDays > 0 {
            parts.append(String(localized: "\(summary.scheduledWorkingDays) scheduled"))
        }
        for definition in catalog.all where definition.expectation == .creditedAbsence {
            let count = summary.count(of: definition.id)
            if count > 0 { parts.append("\(count) \(definition.name.lowercased())") }
        }
        if summary.daysOff > 0 { parts.append(String(localized: "\(summary.daysOff) off")) }
        return parts.joined(separator: "  ·  ")
    }
}
