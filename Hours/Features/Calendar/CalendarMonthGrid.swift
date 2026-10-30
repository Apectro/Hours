import SwiftUI

/// The month grid (design v2, mockup Main, "the month first").
///
/// In the look of Apple's Calendar: no boxes and no tiles, a hairline
/// between weeks, each date in a 32pt circle that is filled with the accent
/// for today. Under the date, the hours worked ("8h", "8.5h"), or a 6pt dot
/// where the day wants a look: red for a working day nobody wrote, the
/// type's own colour for sick, vacation and the other day types. Days off
/// and weekends are in the tertiary label colour. A tap opens the day.
struct CalendarMonthGrid: View {
    let layout: MonthLayout
    let computations: [Int: DayComputation]
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            WeekdayHeader(weekdays: layout.weekdays, formatting: formatting)
                .padding(.bottom, Metrics.small)

            // Rows of plain stacks, not a lazy grid: VoiceOver and the UI
            // tests reach every day of the month without scrolling to it.
            ForEach(rows, id: \.first?.key) { week in
                Rectangle()
                    .fill(.hoursHairlineStyle)
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
                HStack(spacing: Metrics.tiny) {
                    ForEach(week, id: \.key) { date in
                        cell(date)
                            .frame(maxWidth: .infinity)
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
            // A neighbouring month's day is not shown, as in Calendar.
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

/// One day of the month: the date in its circle and, under it, the hours or
/// a dot (see `CalendarMonthGrid`).
struct DayCell: View {
    // The cell grows with the user's text size rather than clipping it.
    // Not `private`: a private stored property makes the memberwise
    // initializer private too.
    @ScaledMetric(relativeTo: .body) var cellHeight: CGFloat = Metrics.dayCellHeight
    @ScaledMetric(relativeTo: .body) var diameter: CGFloat = 32
    @ScaledMetric(relativeTo: .caption2) var underHeight: CGFloat = 13

    let date: CalendarDate
    let computation: DayComputation?
    let isToday: Bool
    let today: CalendarDate
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting

    /// What the day is, which decides what is under the date.
    enum Look: Equatable {
        case written, missing, away, holiday, dayOff, plain
    }

    var body: some View {
        let look = self.look
        VStack(spacing: 2) {
            Text("\(date.day)")
                .font(isToday ? Font.body.weight(.semibold) : Font.body)
                .monospacedDigit()
                .foregroundStyle(numberColor(look))
                .frame(width: diameter, height: diameter)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }
            under(look)
                .frame(height: underHeight)
        }
        .padding(.top, Metrics.tiny)
        .frame(maxWidth: .infinity, minHeight: cellHeight, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(look))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The look

    var look: Look {
        guard let computation else { return .plain }
        if computation.isUnrecordedWorkingDay(asOf: today) { return .missing }
        if computation.dayType.id == .holiday {
            return computation.workedMinutes > 0 ? .written : .holiday
        }
        switch DayKind.of(computation.dayType) {
        case .away:
            return computation.workedMinutes > 0 ? .written : .away
        case .dayOff:
            return computation.workedMinutes > 0 ? .written : .dayOff
        case .worked:
            if computation.dayType.expectation == .zero && computation.workedMinutes == 0 { return .dayOff }
            return computation.hasEntry || computation.workedMinutes > 0 ? .written : .plain
        }
    }

    private func numberColor(_ look: Look) -> Color {
        if isToday { return .white }
        if look == .dayOff { return Color(uiColor: .tertiaryLabel) }
        return .primary
    }

    @ViewBuilder
    private func under(_ look: Look) -> some View {
        if let dot = dotColor(look) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        } else if let text = figure {
            Text(verbatim: text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(figureColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Color.clear
        }
    }

    /// Red for a day nobody wrote; the type's own colour for a day away or
    /// a public holiday; nothing for the rest.
    private func dotColor(_ look: Look) -> Color? {
        guard let computation else { return nil }
        switch look {
        case .missing: return .hoursMissingFill
        case .away, .holiday: return computation.dayType.tint.color
        case .written, .dayOff, .plain: return nil
        }
    }

    /// The figure the calendar settings choose: hours worked ("8.5h"), the
    /// day's balance, or nothing.
    private var figure: String? {
        guard let computation, computation.isIncluded else { return nil }
        switch detail {
        case .hidden:
            return nil
        case .workedHours:
            guard computation.workedMinutes > 0 else { return nil }
            return DurationFormatting.compactHours(
                computation.workedMinutes,
                decimalSeparator: Locale.current.decimalSeparator ?? "."
            )
        case .balance:
            guard computation.hasEntry, computation.balanceMinutes != 0 else { return nil }
            return durationFormatting.signedString(computation.balanceMinutes)
        }
    }

    private var figureColor: Color {
        guard detail == .balance, let computation else { return .secondary }
        return Color.hoursBalance(computation.balanceMinutes)
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
                    .font(.footnote.weight(.semibold))
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
