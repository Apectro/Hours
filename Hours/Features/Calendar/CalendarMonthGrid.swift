import SwiftUI

/// The Today tab's month (the owner's combined mockup, 2026-10-31): worked
/// days on light accent tiles, the hours under the date; days away on a
/// tile in the day type's own colour, with a short word; a working day
/// nobody wrote on an accent tile with a red dot; days off, weekends and
/// days still to come with nothing on them without a tile, the date in the
/// tertiary colour. Today's tile is filled with the accent.
///
/// The first and last rows show the neighbouring months' days too, by the
/// same rules but faded, so a row's week total sits beside the days it
/// counts; a tap on one opens it like any other day. A row with no tile at
/// all (the empty end of a month) is drawn shorter.
///
/// An eighth column on the right holds each row's week total: the whole
/// calendar week's hours worked and credited (`CalendarWeekTotals`), in the
/// app's duration format, as This week. A tap on a day opens it.
struct CalendarMonthGrid: View {
    let layout: MonthLayout
    let computations: [Int: DayComputation]
    /// One per row of the layout, in minutes; empty hides the column.
    let weekTotals: [Int]
    let today: CalendarDate
    let detail: DayCellDetail
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    let onSelect: (CalendarDate) -> Void

    var body: some View {
        CalendarTileGrid(
            layout: layout,
            formatting: formatting,
            weekTotals: weekTotals,
            durationFormatting: durationFormatting,
            totalIdentifier: "calendar-week-total-",
            shortRows: CalendarWeekTotals.shortRows(of: layout, computations: computations, today: today)
        ) { date, height in
            Button {
                onSelect(date)
            } label: {
                DayTile(
                    date: date,
                    computation: computations[date.key],
                    today: today,
                    detail: detail,
                    durationFormatting: durationFormatting,
                    isOutsideMonth: !layout.isInMonth(date),
                    spokenDay: formatting.spokenDay(date, in: layout),
                    height: height
                )
            }
            .buttonStyle(.plain)
            // The label is a spoken sentence and will be translated; a test
            // that matched on it would break on a rewording. The date does
            // not change.
            .accessibilityIdentifier("day-\(date.key)")
            .tourTarget(date == today ? .calendarToday : nil)
        }
    }
}

/// The month grid of tiles both the Today tab and a site's page draw: the
/// weekday letters, the layout's days a week to a row, and an eighth column
/// with each row's week total in the app's duration format. A row with no
/// tile in it is drawn shorter (`shortRows`). What a day looks like and
/// what a tap on it does is the caller's `cell`, given the row's height.
struct CalendarTileGrid<Cell: View>: View {
    // Grows with the user's text size, and fits "44h 18m".
    @ScaledMetric(relativeTo: .footnote) var totalWidth: CGFloat = 58

    let layout: MonthLayout
    let formatting: CalendarFormatting
    /// One per row of the layout, in minutes; empty hides the column.
    let weekTotals: [Int]
    let durationFormatting: DurationFormatting
    /// Each total's identifier is this and its row: "calendar-week-total-0".
    let totalIdentifier: String
    /// One per row: whether it has no tile at all.
    let shortRows: [Bool]
    let cell: (CalendarDate, CGFloat) -> Cell

    static var gap: CGFloat { 4 }
    /// A row with no tile in it, against `Metrics.dayCellHeight`.
    static var shortRowHeight: CGFloat { 40 }

    init(
        layout: MonthLayout,
        formatting: CalendarFormatting,
        weekTotals: [Int],
        durationFormatting: DurationFormatting,
        totalIdentifier: String,
        shortRows: [Bool],
        @ViewBuilder cell: @escaping (CalendarDate, CGFloat) -> Cell
    ) {
        self.layout = layout
        self.formatting = formatting
        self.weekTotals = weekTotals
        self.durationFormatting = durationFormatting
        self.totalIdentifier = totalIdentifier
        self.shortRows = shortRows
        self.cell = cell
    }

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
                        cell(date, rowHeight(index))
                            .frame(maxWidth: .infinity)
                    }
                    if showsTotals {
                        total(row: index)
                    }
                }
            }
        }
    }

    private var showsTotals: Bool { !weekTotals.isEmpty }

    private var rows: [[CalendarDate]] { CalendarWeekTotals.rows(of: layout) }

    private func rowHeight(_ index: Int) -> CGFloat {
        index < shortRows.count && shortRows[index] ? Self.shortRowHeight : Metrics.dayCellHeight
    }

    /// The row's week total, right-aligned, in the app's duration format
    /// ("44h 18m", "44:18"). A week with nothing in it shows nothing; the
    /// column stays so the grid keeps its shape.
    @ViewBuilder
    private func total(row index: Int) -> some View {
        let minutes = index < weekTotals.count ? weekTotals[index] : 0
        if let text = CalendarWeekTotals.label(minutes, formatting: durationFormatting) {
            Text(verbatim: text)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: totalWidth, alignment: .trailing)
                .accessibilityLabel(Text("Sum of the week"))
                .accessibilityValue(Text(verbatim: DurationFormatting(style: .hoursAndMinutes).string(minutes)))
                .accessibilityIdentifier("\(totalIdentifier)\(index)")
        } else {
            Color.clear
                .frame(width: totalWidth, height: 1)
                .accessibilityHidden(true)
        }
    }
}

/// One tile of `CalendarTileGrid`, as drawn: the date (in the week, its
/// weekday letter above), a small figure, word or dot under it, on a
/// rounded fill or none. A neighbouring month's day is faded to about 40%
/// and its date is not bold. Shared by the Today tab's days (`DayTile`)
/// and a site's (`SiteDayTile`), so the two months cannot drift apart.
struct CalendarTileFace<Under: View>: View {
    @ScaledMetric(relativeTo: .body) var height: CGFloat = Metrics.dayCellHeight
    @ScaledMetric(relativeTo: .caption2) var underHeight: CGFloat = 13

    let day: Int
    let weekday: String?
    let isToday: Bool
    let fill: Color?
    let numberColor: Color
    let isBold: Bool
    let isOutsideMonth: Bool
    let accessibilityLabel: String
    let under: Under

    init(
        day: Int,
        weekday: String? = nil,
        isToday: Bool,
        fill: Color?,
        numberColor: Color,
        isBold: Bool,
        isOutsideMonth: Bool = false,
        height: CGFloat = Metrics.dayCellHeight,
        accessibilityLabel: String,
        @ViewBuilder under: () -> Under
    ) {
        self.day = day
        self.weekday = weekday
        self.isToday = isToday
        self.fill = fill
        self.numberColor = numberColor
        self.isBold = isBold
        self.isOutsideMonth = isOutsideMonth
        self.accessibilityLabel = accessibilityLabel
        self.under = under()
        self._height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    var body: some View {
        VStack(spacing: 2) {
            if let weekday {
                Text(verbatim: weekday)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? Color.white : Color.secondary)
            }
            Text(verbatim: "\(day)")
                .font(isBold && !isOutsideMonth ? Font.body.weight(.semibold) : Font.body)
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            under
                .frame(height: underHeight)
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background {
            if let fill {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            }
        }
        .opacity(isOutsideMonth ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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
    let date: CalendarDate
    let computation: DayComputation?
    let today: CalendarDate
    let detail: DayCellDetail
    let durationFormatting: DurationFormatting
    /// The week's tiles: the weekday's letter above the date.
    var weekday: String? = nil
    /// A neighbouring month's day in a month's first or last row: the
    /// same tile, faded, and the date not bold.
    var isOutsideMonth = false
    /// What VoiceOver calls the day: its number, or for a neighbouring
    /// month's day its number and month ("31 October",
    /// `CalendarFormatting.spokenDay`). The number when not given.
    var spokenDay: String? = nil
    /// Before the user's text size; `CalendarTileFace` scales it.
    var height: CGFloat = Metrics.dayCellHeight

    /// What the day is, which decides its tile and what is under the date.
    typealias Look = CalendarDayLook

    private var isToday: Bool { date == today }

    var body: some View {
        let look = self.look
        CalendarTileFace(
            day: date.day,
            weekday: weekday,
            isToday: isToday,
            fill: fill(look),
            numberColor: numberColor(look),
            isBold: hasTile(look),
            isOutsideMonth: isOutsideMonth,
            height: height,
            accessibilityLabel: accessibilityLabel(look)
        ) {
            under(look)
        }
    }

    // MARK: - The look

    var look: Look { CalendarDayLook.of(computation, today: today) }

    private func hasTile(_ look: Look) -> Bool {
        isToday || look.hasTile
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
        // A day of the shown month reads clearly without a tile: a workday
        // (gone by or to come) in the primary colour, a weekend or day off
        // in the secondary one. Only a neighbouring month's day is faded,
        // here and by the tile's own 40%.
        case .plain: return isOutsideMonth ? Color(uiColor: .tertiaryLabel) : .primary
        case .dayOff: return isOutsideMonth ? Color(uiColor: .tertiaryLabel) : .secondary
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
        var parts: [String] = [spokenDay ?? "\(date.day)"]
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
