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
            HStack(spacing: Metrics.tiny) {
                ForEach(layout.weekdays, id: \.self) { weekday in
                    Text(formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(formatting.weekdayName(for: weekday))
                }
            }

            LazyVGrid(columns: columns, spacing: Metrics.tiny) {
                ForEach(layout.days, id: \.key) { date in
                    DayCell(
                        date: date,
                        computation: computations[date.key],
                        isInMonth: layout.isInMonth(date),
                        isSelected: date == selectedDate,
                        isToday: date == today,
                        isPast: date < today,
                        detail: detail,
                        durationFormatting: durationFormatting
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(date) }
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
    @ScaledMetric(relativeTo: .subheadline) var numberDiameter: CGFloat = 28

    let date: CalendarDate
    let computation: DayComputation?
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isPast: Bool
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.accentColor)
                } else if isToday {
                    Circle().stroke(Color.accentColor, lineWidth: 1.5)
                }
                Text("\(date.day)")
                    .font(.system(.subheadline, design: .rounded, weight: isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(numberColor)
            }
            .frame(width: numberDiameter, height: numberDiameter)

            detailLabel
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background { background }
        .opacity(isInMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var detailLabel: some View {
        if let text = detailText {
            Text(text)
                .font(.caption2.weight(.medium))
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

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        ZStack {
            shape.fill(washColor)
            if isMissingData {
                // A working day in the past with nothing recorded. Quiet, but
                // impossible to miss when scanning a month.
                shape.strokeBorder(Color.hoursSubdued, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
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

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
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
        guard isInMonth, isPast, !isToday, let computation else { return false }
        return computation.isScheduledWorkingDay && !computation.hasEntry && computation.workedMinutes == 0
    }

    private var accessibilityLabel: String {
        var parts: [String] = ["\(date.day)"]
        if let computation {
            parts.append(computation.dayType.name)
            if computation.workedMinutes > 0 {
                parts.append(DurationFormatting(style: .hoursAndMinutes).string(computation.workedMinutes) + " worked")
            }
            if isMissingData { parts.append("no hours recorded") }
        }
        if isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }
}
