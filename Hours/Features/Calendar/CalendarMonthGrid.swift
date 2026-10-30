import SwiftUI

/// The month grid (1.2, mockup Today, "The month").
///
/// Reads at a glance and nothing more, by the colour rule: a written day is
/// white with its figure; a day not written has a dashed red outline and a
/// "?"; away (sick, leave) is an orange wash with the type's name; a public
/// holiday is green; a day off is grey; today is filled with the accent. A
/// tap opens the day.
struct CalendarMonthGrid: View {
    let layout: MonthLayout
    let computations: [Int: DayComputation]
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    var body: some View {
        VStack(spacing: Metrics.small) {
            WeekdayHeader(weekdays: layout.weekdays, formatting: formatting)

            // Rows of plain stacks, not a lazy grid: the month sits under
            // Today, below the fold, and a lazy grid would not build cells
            // that are off screen — VoiceOver and the UI tests could not
            // reach today's day until it was scrolled to.
            VStack(spacing: Metrics.tiny) {
                ForEach(rows, id: \.first?.key) { week in
                    HStack(spacing: Metrics.tiny) {
                        ForEach(week, id: \.key) { date in
                            cell(date)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    /// The layout's days, a week to a row.
    private var rows: [[CalendarDate]] {
        let width = max(layout.columnCount, 1)
        return stride(from: 0, to: layout.days.count, by: width).map {
            Array(layout.days[$0..<min($0 + width, layout.days.count)])
        }
    }

    @ViewBuilder
    private func cell(_ date: CalendarDate) -> some View {
        if layout.isInMonth(date) {
            Button {
                onSelect(date)
            } label: {
                DayCell(
                    date: date,
                    computation: computations[date.key],
                    isToday: date == today,
                    today: today,
                    detail: detail,
                    durationFormatting: durationFormatting
                )
            }
            .buttonStyle(.plain)
            // The label is a spoken sentence and will be translated; a test
            // that matched on it would break on a rewording. The date does
            // not change.
            .accessibilityIdentifier("day-\(date.key)")
            .tourTarget(date == today ? .calendarToday : nil)
        } else {
            // A neighbouring month's day: an empty place, as on a paper
            // calendar.
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

/// One day of the month, drawn by the colour rule.
struct DayCell: View {
    // The cell grows with the user's text size rather than clipping it.
    // Not `private`: a private stored property makes the memberwise
    // initializer private too.
    @ScaledMetric(relativeTo: .subheadline) var cellHeight: CGFloat = Metrics.dayCellHeight

    let date: CalendarDate
    let computation: DayComputation?
    let isToday: Bool
    let today: CalendarDate
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting

    @Environment(\.highContrast) private var highContrast

    /// What the day is, which decides its colours.
    enum Look: Equatable {
        case written, missing, away, holiday, dayOff, plain, today
    }

    var body: some View {
        let look = self.look
        VStack(spacing: 1) {
            Text("\(date.day)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(numberColor(look))
            detailLabel(look)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: cellHeight)
        .background { background(look) }
        .overlay(alignment: .topTrailing) { workedHolidayMark(look) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(look))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The look

    var look: Look {
        if isToday { return .today }
        guard let computation else { return .plain }
        if computation.isUnrecordedWorkingDay(asOf: today) { return .missing }
        if computation.dayType.id == .holiday { return .holiday }
        switch DayKind.of(computation.dayType) {
        case .away:
            return .away
        case .dayOff:
            return computation.workedMinutes > 0 ? .written : .dayOff
        case .worked:
            if computation.dayType.expectation == .zero && computation.workedMinutes == 0 { return .dayOff }
            return computation.hasEntry || computation.workedMinutes > 0 ? .written : .plain
        }
    }

    private func numberColor(_ look: Look) -> Color {
        switch look {
        case .today: return .white
        case .missing: return .hoursMissing
        case .away: return .hoursAttention
        case .holiday: return .hoursPositive
        case .dayOff: return .secondary
        case .written, .plain: return .primary
        }
    }

    @ViewBuilder
    private func detailLabel(_ look: Look) -> some View {
        if let text = detailText(look) {
            Text(verbatim: text)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(detailColor(look))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 2)
        } else {
            Text(verbatim: " ")
                .font(.caption2)
                .accessibilityHidden(true)
        }
    }

    private func detailText(_ look: Look) -> String? {
        guard let computation else { return nil }
        switch look {
        case .missing:
            return "?"
        case .away:
            return computation.workedMinutes > 0 ? figure(computation) : computation.dayType.displayName()
        case .dayOff, .plain:
            return nil
        case .holiday, .written, .today:
            return figure(computation)
        }
    }

    /// The figure the calendar settings choose: hours worked, the day's
    /// balance, or nothing.
    private func figure(_ computation: DayComputation) -> String? {
        guard computation.isIncluded else { return nil }
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

    private func detailColor(_ look: Look) -> Color {
        switch look {
        case .today: return .white
        case .missing: return .hoursMissing
        case .away: return .hoursAttention
        case .holiday: return .hoursPositive
        default:
            guard detail == .balance, let computation else { return .secondary }
            return Color.hoursBalance(computation.balanceMinutes)
        }
    }

    @ViewBuilder
    private func background(_ look: Look) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        switch look {
        case .today:
            shape.fill(Color.accentColor)
        case .missing:
            shape.fill(Color.hoursSurface)
                .overlay {
                    shape.strokeBorder(Color.hoursMissing, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
        case .away:
            shape.fill(Color.hoursAttentionFill.opacity(highContrast ? 0.22 : 0.14))
        case .holiday:
            shape.fill(Color.hoursPositive.opacity(highContrast ? 0.22 : 0.14))
        case .dayOff:
            shape.fill(Color.hoursSubdued.opacity(highContrast ? 0.30 : 0.18))
        case .written, .plain:
            shape.fill(Color.hoursSurface)
        }
    }

    /// A public holiday that was worked as well as paid: the holiday's wash
    /// stays, and a small hammer in the corner says the hours are on top.
    @ViewBuilder
    private func workedHolidayMark(_ look: Look) -> some View {
        if let computation, computation.isWorkedPublicHoliday {
            Image(systemName: "hammer.fill")
                .font(.system(.caption2, design: .rounded))
                .imageScale(.small)
                .foregroundStyle(look == .today ? Color.white : Color.hoursPositive)
                .padding(3)
                .accessibilityHidden(true)
        }
    }

    private func accessibilityLabel(_ look: Look) -> String {
        let duration = DurationFormatting(style: .hoursAndMinutes)
        var parts: [String] = ["\(date.day)"]
        if let computation {
            parts.append(computation.dayType.displayName())
            if computation.workedMinutes > 0 {
                parts.append(String(
                    localized: "\(duration.string(computation.workedMinutes)) worked",
                    comment: "VoiceOver, the hours worked on a calendar day"
                ))
            }
            // Whether the day ran over or short is said out loud: a colour
            // is not information to someone using VoiceOver.
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
            if look == .missing {
                parts.append(String(localized: "not written", comment: "VoiceOver, a past working day with nothing recorded"))
            }
        }
        if isToday { parts.append(String(localized: "today", comment: "VoiceOver, the calendar's today")) }
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
