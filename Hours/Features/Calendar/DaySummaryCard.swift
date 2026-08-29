import SwiftUI

/// The selected day, shown inline under the calendar.
///
/// Reading a day should not cost a sheet. Editing does.
struct DaySummaryCard: View {
    let computation: DayComputation
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onEdit: () -> Void
    /// Present only on today, and only when no clock is already running.
    var onClockIn: (() -> Void)? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                header

                if computation.hasEntry || computation.workedMinutes > 0 {
                    Divider()
                    figures
                } else {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !computation.note.isEmpty {
                    Text(computation.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                warnings

                if let onClockIn {
                    Button(action: onClockIn) {
                        Label("Clock in", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button(action: onEdit) {
                        Label(
                            computation.hasEntry ? "Edit day" : "Add hours by hand",
                            systemImage: computation.hasEntry ? "square.and.pencil" : "plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else {
                    Button(action: onEdit) {
                        Label(
                            computation.hasEntry ? "Edit day" : "Add hours",
                            systemImage: computation.hasEntry ? "square.and.pencil" : "plus"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            DayTypeBadge(definition: computation.dayType, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatting.fullDate(computation.date))
                    .font(.headline)
                HStack(spacing: Metrics.tiny) {
                    Text(computation.dayType.name)
                    if let holidayName = computation.holidayName {
                        Text("·")
                        Text(holidayName)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if settings.features.showsBalance && computation.hasEntry {
                BalanceText(
                    minutes: computation.balanceMinutes,
                    formatting: duration,
                    font: .hoursFigure(.title3)
                )
            }
        }
    }

    private var figures: some View {
        VStack(spacing: Metrics.small) {
            if computation.isSplitShift {
                // Each block gets its own line: the time between them is
                // neither worked nor a break, and one merged range would say
                // the opposite.
                ForEach(computation.shifts.indices, id: \.self) { position in
                    MetricRow(
                        label: String(localized: "Block \(position + 1)"),
                        value: shiftRange(computation.shifts[position]),
                        systemImage: position == 0 ? "clock" : "clock.arrow.circlepath"
                    )
                }
            } else if let start = computation.start, let end = computation.end {
                MetricRow(
                    label: String(localized: "Hours"),
                    value: "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
                        + (computation.crossesMidnight ? " (+1)" : ""),
                    systemImage: "clock"
                )
            }
            if settings.features.trackBreaks && computation.breakMinutes > 0 {
                MetricRow(label: String(localized: "Break"), value: duration.string(computation.breakMinutes), systemImage: "cup.and.saucer")
            }
            MetricRow(
                label: String(localized: "Worked"),
                value: duration.string(computation.workedMinutes),
                systemImage: "timer"
            )
            if computation.creditedMinutes > 0 {
                MetricRow(
                    label: String(localized: "Paid absence"),
                    value: duration.string(computation.creditedMinutes),
                    systemImage: "checkmark.seal"
                )
            }
            if settings.features.trackExpectedHours {
                MetricRow(label: String(localized: "Expected"), value: duration.string(computation.expectedMinutes), systemImage: "target")
            }
            if computation.adjustmentMinutes != 0 {
                MetricRow(
                    label: computation.adjustmentReason.title,
                    value: duration.signedString(computation.adjustmentMinutes),
                    tint: Color.hoursBalance(computation.adjustmentMinutes),
                    systemImage: computation.adjustmentReason.symbolName
                )
            }
            if settings.features.trackLocation && !computation.location.isEmpty {
                MetricRow(label: String(localized: "Location"), value: computation.location, systemImage: "mappin.and.ellipse")
            }
            if settings.features.trackTags && !computation.tags.isEmpty {
                MetricRow(label: String(localized: "Tags"), value: computation.tags.joined(separator: ", "), systemImage: "tag")
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        let visible = computation.warnings.filter { $0.isProblem || $0 == .excludedFromTotals }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(visible) { warning in
                    Label(warning.message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shiftRange(_ shift: ShiftPeriod) -> String {
        guard let start = shift.start, let end = shift.end else { return "—" }
        let range = "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
        return range + (shift.crossesMidnight ? " (+1)" : "")
    }

    private var emptyMessage: String {
        switch computation.dayType.expectation {
        case .scheduled:
            return computation.expectedMinutes > 0
                ? String(
                    localized: "Nothing recorded yet. \(duration.string(computation.expectedMinutes)) expected.",
                    comment: "An empty working day, with the hours its schedule expects"
                  )
                : String(localized: "Nothing recorded yet.")
        case .zero:
            return String(localized: "Not a working day.")
        case .creditedAbsence:
            return "\(duration.string(computation.creditedMinutes)) credited."
        }
    }
}
