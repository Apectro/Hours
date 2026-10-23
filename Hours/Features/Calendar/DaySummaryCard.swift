import SwiftUI

/// The selected day, shown inline under the calendar.
///
/// Reading a day should not cost a sheet. Editing does.
struct DaySummaryCard: View {
    let computation: DayComputation
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onEdit: () -> Void
    /// "I worked" on a public holiday off: opens the editor with the day's
    /// times filled in, and the holiday still paid.
    var onWorkedHoliday: (() -> Void)? = nil
    /// Present only on today, and only when no clock is already running.
    var onClockIn: (() -> Void)? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                header

                if isPublicHolidayOff {
                    publicHolidayChoice
                } else if computation.hasEntry || computation.workedMinutes > 0 {
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
                    .accessibilityIdentifier("day-card-edit")
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
                    .accessibilityIdentifier("day-card-edit")
                }
            }
        }
    }

    // MARK: - Public holidays

    /// A holiday rule's paid day off, whether worked or not.
    private var isPublicHoliday: Bool {
        computation.holidayName != nil && computation.dayType.id == .holiday
    }

    /// Nothing worked on it: the choice between leaving it and "I worked".
    private var isPublicHolidayOff: Bool {
        isPublicHoliday && computation.workedMinutes == 0 && !computation.hasEntry && onWorkedHoliday != nil
    }

    private var publicHolidayChoice: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Label {
                Text("Day off (paid)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            .accessibilityIdentifier("day-card-holiday-off")
            if computation.creditedMinutes > 0 {
                Text(String(
                    localized: "\(duration.string(computation.creditedMinutes)) credited.",
                    comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                onWorkedHoliday?()
            } label: {
                Label("I worked", systemImage: "hammer")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
            .accessibilityIdentifier("day-card-holiday-worked")
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
                    if isPublicHoliday, let holidayName = computation.holidayName {
                        // "Christmas Day · public holiday"
                        Text(holidayName)
                        Text("·")
                        Text("public holiday")
                    } else {
                        Text(computation.dayType.displayName())
                        if let holidayName = computation.holidayName {
                            Text("·")
                            Text(holidayName)
                        }
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
            return String(
                localized: "\(duration.string(computation.creditedMinutes)) credited.",
                comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
            )
        }
    }
}
