import SwiftUI

/// The Today tab's month (the owner's combined mockup, 2026-10-31): worked
/// days on light accent tiles, the hours under the date; days away on a
/// tile in the day type's own colour, with a short word; a working day
/// nobody wrote on an accent tile with a red dot; days off, weekends and
/// days still to come with nothing on them without a tile, the date in the
/// tertiary colour. Today's tile is filled with the accent.
///
/// An eighth column on the right holds each row's week total: the whole
/// calendar week's hours worked and credited (`CalendarWeekTotals`), even
/// where the row runs into the month before or after. A tap on a day opens
/// it.
struct CalendarMonthGrid: View {
    // Grows with the user's text size. Not `private`: a private stored
    // property makes the memberwise initializer private too.
    @ScaledMetric(relativeTo: .subheadline) var totalWidth: CGFloat = 46

    let layout: MonthLayout
    let computations: [Int: DayComputation]
    /// One per row of the layout, in minutes; empty hides the column.
    let weekTotals: [Int]
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    static let gap: CGFloat = 4

    var body: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                ForEach(layout.weekdays, id: \.self) { weekday in
                    Text(verbatim: formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text(verbatim: formatting.weekdayName(for: weekday)))
                }
                if showsTotals {
                    // The totals column has no heading.
                    Color.clear
                        .frame(width: totalWidth, height: 1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 2)

            // Rows of plain stacks, not a lazy grid: VoiceOver and the UI
            // tests reach every day of the month without scrolling to it.
            ForEach(Array(rows.enumerated()), id: \.offset) { index, week in
                HStack(spacing: Self.gap) {
                    ForEach(week, id: \.key) { date in
                        cell(date)
                            .frame(maxWidth: .infinity)
                    }
                    if showsTotals {
                        total(row: index, week: week)
                    }
                }
            }
        }
    }

    private var showsTotals: Bool { !weekTotals.isEmpty }

    private var rows: [[CalendarDate]] { CalendarWeekTotals.rows(of: layout) }

    @ViewBuilder
    private func cell(_ date: CalendarDate) -> some View {
        if layout.isInMonth(date) {
            Button {
                onSelect(date)
            } label: {
                DayTile(
                    date: date,
                    computation: computations[date.key],
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

    /// The row's week total, right-aligned: "40h". A week still to come
    /// with nothing in it shows nothing rather than "0h".
    private func total(row index: Int, week: [CalendarDate]) -> some View {
        let minutes = index < weekTotals.count ? weekTotals[index] : 0
        let isAhead = (week.first.map { $0 > today }) ?? false
        let text = minutes > 0
            ? DurationFormatting.compactHours(minutes, decimalSeparator: Locale.current.decimalSeparator ?? ".")
            : (isAhead ? "" : "0h")
        return Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: totalWidth, alignment: .trailing)
            .accessibilityLabel(Text("Sum of the week"))
            .accessibilityValue(Text(verbatim: DurationFormatting(style: .hoursAndMinutes).string(minutes)))
            .accessibilityIdentifier("calendar-week-total-\(index)")
    }
}

/// The calendar's week (the owner's combined mockup, phone 2): the week's
/// days as tall tiles, each with its weekday letter, the date and the
/// hours, by the month's colour rules. Same identifiers as the month's
/// days.
struct CalendarWeekTiles: View {
    let layout: MonthLayout
    let computations: [Int: DayComputation]
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(layout.days, id: \.key) { date in
                Button {
                    onSelect(date)
                } label: {
                    DayTile(
                        date: date,
                        computation: computations[date.key],
                        today: today,
                        detail: detail,
                        durationFormatting: durationFormatting,
                        weekday: formatting.veryShortWeekdaySymbol(for: date.weekday(in: formatting.calendar)),
                        height: 84
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(date.key)")
                .tourTarget(date == today ? .calendarToday : nil)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One day on its tile (see `CalendarMonthGrid`): the date, and under it
/// the hours, a short word for a day away, or a red dot for a working day
/// nobody wrote. In the week, the weekday letter above.
struct DayTile: View {
    @ScaledMetric(relativeTo: .body) var height: CGFloat = Metrics.dayCellHeight
    @ScaledMetric(relativeTo: .caption2) var underHeight: CGFloat = 13

    let date: CalendarDate
    let computation: DayComputation?
    let today: CalendarDate
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting
    /// The week's tiles: the weekday's letter above the date.
    let weekday: String?

    init(
        date: CalendarDate,
        computation: DayComputation?,
        today: CalendarDate,
        detail: DayCellDetail,
        durationFormatting: DurationFormatting,
        weekday: String? = nil,
        height: CGFloat = Metrics.dayCellHeight
    ) {
        self.date = date
        self.computation = computation
        self.today = today
        self.detail = detail
        self.durationFormatting = durationFormatting
        self.weekday = weekday
        self._height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    /// What the day is, which decides its tile and what is under the date.
    enum Look: Equatable {
        case written, missing, away, holiday, dayOff, plain
    }

    private var isToday: Bool { date == today }

    var body: some View {
        let look = self.look
        VStack(spacing: 2) {
            if let weekday {
                Text(verbatim: weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.white : Color.secondary)
            }
            Text(verbatim: "\(date.day)")
                .font(hasTile(look) ? Font.body.weight(.semibold) : Font.body)
                .monospacedDigit()
                .foregroundStyle(numberColor(look))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            under(look)
                .frame(height: underHeight)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background {
            if let fill = fill(look) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func hasTile(_ look: Look) -> Bool {
        isToday || fill(look) != nil
    }

    /// The day type's own colour, for a day away or a public holiday.
    private var typeColor: Color {
        computation?.dayType.tint.color ?? .secondary
    }

    /// The type's colour, darkened in Light mode and lightened in Dark so
    /// it reads as text on its own wash.
    private var typeTextColor: Color {
        typeColor.mix(with: .primary, by: 0.35)
    }

    private func fill(_ look: Look) -> Color? {
        if isToday { return .accentColor }
        switch look {
        case .written, .missing: return Color.accentColor.opacity(0.14)
        case .away, .holiday: return typeColor.opacity(0.16)
        case .dayOff, .plain: return nil
        }
    }

    private func numberColor(_ look: Look) -> Color {
        if isToday { return .white }
        switch look {
        case .written, .missing: return .primary
        case .away, .holiday: return typeTextColor
        case .dayOff, .plain: return Color(uiColor: .tertiaryLabel)
        }
    }

    @ViewBuilder
    private func under(_ look: Look) -> some View {
        switch look {
        case .missing where !isToday:
            Circle()
                .fill(Color.hoursMissingFill)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        case .away, .holiday:
            Text(verbatim: shortWord)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.white : typeTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        default:
            if let text = figure {
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
    }

    /// "Sick", "Leave", "Holiday"; any other type by its own name, shrunk
    /// to fit.
    private var shortWord: String {
        guard let computation else { return "" }
        switch computation.dayType.id {
        case .sick: return String(localized: "Sick")
        case .vacation: return String(localized: "Leave")
        case .holiday: return String(localized: "Holiday")
        default: return computation.dayType.displayName()
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
        if isToday { return .white }
        guard detail == .balance, let computation else { return .accentColor }
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
