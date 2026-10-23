import SwiftUI

/// The month grid.
///
/// Reads at a glance and nothing more: a number, at most one short figure, and
/// a colour wash for the kind of day. Anything else belongs in the day summary
/// underneath.
struct CalendarMonthGrid: View {
    let layout: MonthLayout
    let computations: [Int: DayComputation]
    let selectedDate: CalendarDate
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.tiny), count: max(layout.columnCount, 1))
    }

    var body: some View {
        VStack(spacing: Metrics.small) {
            WeekdayHeader(weekdays: layout.weekdays, formatting: formatting)

            LazyVGrid(columns: columns, spacing: Metrics.tiny) {
                ForEach(layout.days, id: \.key) { date in
                    DayCell(
                        date: date,
                        computation: computations[date.key],
                        isInMonth: layout.isInMonth(date),
                        isSelected: date == selectedDate,
                        isToday: date == today,
                        today: today,
                        detail: detail,
                        durationFormatting: durationFormatting
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(date) }
                    .tourTarget(date == today ? .calendarToday : nil)
                }
            }
        }
    }
}

/// One day.
struct DayCell: View {
    // The cell grows with the user's text size rather than clipping it.
    // Not `private`: a private stored property makes the memberwise
    // initializer private too.
    @ScaledMetric(relativeTo: .subheadline) var cellHeight: CGFloat = Metrics.dayCellHeight

    let date: CalendarDate
    let computation: DayComputation?
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let today: CalendarDate
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting

    var body: some View {
        VStack(spacing: 2) {
            DayNumberCircle(day: date.day, isSelected: isSelected, isToday: isToday)

            detailLabel
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background { DayCellBackground(wash: washColor, isMissing: isMissingData) }
        .overlay(alignment: .topTrailing) { workedHolidayMark }
        .opacity(isInMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The label is a spoken sentence and will be translated; a test that
        // matched on it would break on a rewording. The date does not change.
        .accessibilityIdentifier("day-\(date.key)")
    }

    // MARK: - Pieces

    /// A public holiday that was worked as well as paid: the holiday's wash
    /// stays, and a small hammer in the corner says the hours are on top.
    @ViewBuilder
    private var workedHolidayMark: some View {
        if let computation, computation.isWorkedPublicHoliday {
            Image(systemName: "hammer.fill")
                .font(.system(.caption2, design: .rounded))
                .imageScale(.small)
                .foregroundStyle(computation.dayType.tint.color)
                .padding(3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var detailLabel: some View {
        if let text = detailText {
            Text(text)
                // Rounded, to match the day number above it. `.caption2` alone
                // lost that when the cell was made to scale with Dynamic Type.
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let computation, computation.hasContent {
            Circle()
                .fill(computation.dayType.tint.color)
                .frame(width: 5, height: 5)
        } else {
            Color.clear.frame(width: 5, height: 5)
        }
    }

    private var washColor: Color {
        guard let computation else { return .clear }
        switch computation.dayType.expectation {
        case .scheduled:
            return computation.hasEntry ? computation.dayType.tint.color.opacity(0.08) : .clear
        case .zero:
            return Color.hoursSubdued.opacity(0.10)
        case .creditedAbsence:
            return computation.dayType.tint.color.opacity(0.16)
        }
    }

    private var detailText: String? {
        guard let computation, computation.isIncluded else { return nil }
        switch detail {
        case .hidden:
            return nil
        case .workedHours:
            guard computation.workedMinutes > 0 else { return nil }
            return DurationFormatting(style: .clock).string(computation.workedMinutes)
        case .balance:
            guard computation.hasEntry, computation.balanceMinutes != 0 else { return nil }
            return durationFormatting.signedString(computation.balanceMinutes)
        }
    }

    private var detailColor: Color {
        guard detail == .balance, let computation else { return .secondary }
        return Color.hoursBalance(computation.balanceMinutes)
    }

    private var isMissingData: Bool {
        guard isInMonth, let computation else { return false }
        return computation.isUnrecordedWorkingDay(asOf: today)
    }

    private var accessibilityLabel: String {
        let duration = DurationFormatting(style: .hoursAndMinutes)
        var parts: [String] = ["\(date.day)"]
        if let computation {
            parts.append(computation.dayType.displayName())
            if computation.workedMinutes > 0 {
                parts.append(duration.string(computation.workedMinutes) + " worked")
            }
            // Whether the day ran over or short is said out loud, because the
            // only other place it appears is the cell's tint — and a colour is
            // not information to someone using VoiceOver, nor to the one man in
            // twelve who cannot tell this particular green from this red.
            if computation.balanceMinutes != 0 {
                let magnitude = duration.string(abs(computation.balanceMinutes))
                parts.append(computation.balanceMinutes > 0
                    ? String(localized: "\(magnitude) over",
                             comment: "VoiceOver, a day worked longer than expected")
                    : String(localized: "\(magnitude) short",
                             comment: "VoiceOver, a day worked less than expected"))
            }
            if computation.isWorkedPublicHoliday {
                parts.append(String(localized: "worked on a public holiday",
                                    comment: "VoiceOver, a calendar day that is a public holiday and was worked"))
            }
            if isMissingData { parts.append("no hours recorded") }
        }
        if isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Shared with the site's month

/// The single-letter weekday names above a month grid, starting on the
/// calendar's own first weekday. Shared by the calendar and a site's month so
/// the two grids line up the same way.
struct WeekdayHeader: View {
    let weekdays: [Int]
    let formatting: CalendarFormatting

    var body: some View {
        HStack(spacing: Metrics.tiny) {
            ForEach(weekdays, id: \.self) { weekday in
                Text(formatting.veryShortWeekdaySymbol(for: weekday))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(formatting.weekdayName(for: weekday))
            }
        }
    }
}

/// A day's number in its circle: filled with the accent when selected, ringed
/// with it for today. One view for every month grid in the app, so a site's
/// month and the calendar can never drift apart in how a day looks.
struct DayNumberCircle: View {
    // Grows with the user's text size, like the cell around it. Not
    // `private`, so the memberwise initializer stays usable.
    @ScaledMetric(relativeTo: .subheadline) var diameter: CGFloat = 28

    let day: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(Color.accentColor)
            } else if isToday {
                Circle().stroke(Color.accentColor, lineWidth: 1.5)
            }
            Text("\(day)")
                .font(.system(.subheadline, design: .rounded, weight: isToday || isSelected ? .bold : .regular))
                .foregroundStyle(numberColor)
        }
        .frame(width: diameter, height: diameter)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }
}

/// The rounded shape behind a day: a colour wash, and the dashed outline for
/// a working day in the past with nothing recorded — quiet, but impossible to
/// miss when scanning a month.
struct DayCellBackground: View {
    let wash: Color
    let isMissing: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        ZStack {
            shape.fill(wash)
            if isMissing {
                shape.strokeBorder(Color.hoursSubdued, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}
