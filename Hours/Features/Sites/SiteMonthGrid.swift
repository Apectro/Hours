import SwiftUI

// MARK: - A site's month by status (design v2)

extension SiteDayStatus {
    /// The dot under a day of the site's month: green written, orange
    /// someone missing, red not written; nothing for a day off or a day
    /// still to come.
    var dot: Color? {
        switch self {
        case .written: return .hoursDone
        case .partly: return .hoursAttentionFill
        case .missing: return .hoursMissingFill
        case .dayOff, .future, .noWork, .elsewhere: return nil
        }
    }

    /// What VoiceOver says for the status.
    var title: String {
        switch self {
        case .written: return String(localized: "Written")
        case .partly: return String(localized: "Partly written")
        case .missing: return String(localized: "Not written")
        case .dayOff: return String(localized: "Day off")
        case .future: return String(localized: "Still to come")
        case .noWork: return String(localized: "No work")
        case .elsewhere: return String(localized: "Crew on another site")
        }
    }
}

extension SiteCalendarDayLook {
    /// What VoiceOver says for the look, after the date and before the
    /// holiday: the status's word, "Paused" for a paused site's work day.
    /// A holiday says its name and "Holiday" instead (`SiteDayTile`).
    var statusTitle: String {
        switch kind {
        case .written: return SiteDayStatus.written.title
        case .partly: return SiteDayStatus.partly.title
        case .missing: return SiteDayStatus.missing.title
        case .future: return SiteDayStatus.future.title
        case .noWork: return SiteDayStatus.noWork.title
        case .elsewhere: return SiteDayStatus.elsewhere.title
        case .paused: return String(localized: "Paused")
        case .dayOff, .holiday: return SiteDayStatus.dayOff.title
        }
    }
}

/// A site's month on its own page, in the Today tab's look
/// (`CalendarTileGrid`): a written day on an accent tile with "• 5" under
/// the date, the people on it (you included when listed), orange while
/// someone on the crew is neither ticked nor given a reason; a work day
/// before today nobody wrote on a tile with a red dot; a public holiday on a
/// tile in the holiday type's colour with "Holiday" under the date, as the
/// Today tab draws it, and a written holiday with a small flag beside its
/// people; days off, paused days and days still to come without a tile, the
/// date in the tertiary colour; today's tile filled. The first and last
/// rows show the neighbouring months' days, faded. The eighth column is the
/// crew's hours on the site in each row's whole week. A day opens that day
/// on the site.
struct SiteMonthCalendar: View {
    let layout: MonthLayout
    /// Every drawn day (`SiteCalendarGrid.looks`).
    let looks: [CalendarDate: SiteCalendarDayLook]
    /// People present on each written day (`SiteCalendarGrid.people`).
    let people: [CalendarDate: Int]
    /// One per row, in minutes (`SiteCalendarGrid.weekMinutes`).
    let weekTotals: [Int]
    let today: CalendarDate
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    /// Why nobody worked, on each day recorded as "no work".
    var noWork: [CalendarDate: SiteNoWorkReason] = [:]
    /// The public holiday type's own colour, as the Today tab draws a
    /// holiday (`DayTile`).
    var holidayTint: Color = .purple
    /// Opens a day on the site. Buttons rather than links: the month is one
    /// row of a List, where links would make the whole row one.
    let onSelect: (CalendarDate) -> Void

    var body: some View {
        CalendarTileGrid(
            layout: layout,
            formatting: formatting,
            weekTotals: weekTotals,
            durationFormatting: durationFormatting,
            totalIdentifier: "site-week-total-",
            shortRows: SiteCalendarGrid.shortRows(of: layout, looks: looks, today: today)
        ) { date, height in
            Button {
                onSelect(date)
            } label: {
                SiteDayTile(
                    date: date,
                    look: looks[date] ?? SiteCalendarDayLook(kind: .dayOff),
                    people: people[date] ?? 0,
                    noWork: noWork[date],
                    isToday: date == today,
                    isOutsideMonth: !layout.isInMonth(date),
                    spokenDay: formatting.spokenDay(date, in: layout),
                    holidayTint: holidayTint,
                    height: height
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("site-overview-day-\(date.key)")
        }
    }
}

/// One day of `SiteMonthCalendar`, on the Today tab's tile
/// (`CalendarTileFace`).
private struct SiteDayTile: View {
    let date: CalendarDate
    let look: SiteCalendarDayLook
    let people: Int
    let noWork: SiteNoWorkReason?
    let isToday: Bool
    let isOutsideMonth: Bool
    /// "1", or "31 October" for a neighbouring month's day
    /// (`CalendarFormatting.spokenDay`).
    let spokenDay: String
    let holidayTint: Color
    let height: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .caption2) private var flagSize: CGFloat = 7

    var body: some View {
        CalendarTileFace(
            day: date.day,
            isToday: isToday,
            fill: fill,
            numberColor: numberColor,
            isBold: isToday || look.hasTile,
            isOutsideMonth: isOutsideMonth,
            height: height,
            accessibilityLabel: accessibilityLabel
        ) {
            under
        }
    }

    /// The holiday type's colour, darkened in Light mode and lightened in
    /// Dark so it reads as text on its own wash, as on the Today tab.
    private var holidayTextColor: Color {
        holidayTint.mix(with: .primary, by: 0.35)
    }

    private var fill: Color? {
        if isToday { return .accentColor }
        switch look.kind {
        case .written, .partly, .missing: return Color.accentColor.opacity(0.14)
        case .holiday: return holidayTint.opacity(0.16)
        case .future, .noWork, .elsewhere, .paused, .dayOff: return nil
        }
    }

    private var numberColor: Color {
        if isToday { return .white }
        if look.kind == .holiday { return holidayTextColor }
        if look.hasTile { return .primary }
        // A day of the shown month reads clearly without a tile: a workday
        // to come in the primary colour, a day off in the secondary one.
        // Only a neighbouring month's day is faded, here and by the tile's
        // own 40%.
        if isOutsideMonth { return Color(uiColor: .tertiaryLabel) }
        return look.isNeutral ? .secondary : .primary
    }

    /// "• 5" on a written day, orange while partly written, a small flag
    /// before it on a holiday; "Holiday" on a holiday nobody worked; a red
    /// dot on a day nobody wrote; "No work" on a day nobody worked; nothing
    /// on a day off or a day to come.
    @ViewBuilder
    private var under: some View {
        switch look.kind {
        case .written, .partly:
            HStack(spacing: 2) {
                if look.hasHolidayMark { holidayFlag }
                if people > 0 {
                    Text(verbatim: "• \(people)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(peopleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        case .missing where !isToday:
            Circle()
                .fill(Color.hoursMissingFill)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
        case .holiday:
            // The Today tab's word for a public holiday, in its colour.
            Text("Holiday")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.white : holidayTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
        case .noWork:
            // A small grey word, no colour: nobody worked, for a reason.
            HStack(spacing: 2) {
                if look.hasHolidayMark { holidayFlag }
                Text("No work")
                    .font(.caption2)
                    .foregroundStyle(isToday ? Color.white : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
        default:
            if look.hasHolidayMark {
                holidayFlag
            } else {
                Color.clear
            }
        }
    }

    /// The small holiday mark on a holiday something else is drawn on.
    private var holidayFlag: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: flagSize, weight: .semibold))
            .foregroundStyle(isToday ? Color.white : holidayTextColor)
            .accessibilityHidden(true)
    }

    private var peopleColor: Color {
        if isToday { return .white }
        return look.kind == .partly ? .hoursAttention : .accentColor
    }

    /// "1 November, All Saints' Day, Holiday"; "18, Written, 5 people,
    /// Remembrance Day, Holiday"; "3, No work · Day off"; ", Today" last.
    private var accessibilityLabel: String {
        var parts = [spokenDay]
        if look.kind != .holiday {
            parts.append(noWork.map(\.summary) ?? look.statusTitle)
        }
        if people > 0, look.kind == .written || look.kind == .partly {
            parts.append(String(inflected: "^[\(people) person](inflect: true)"))
        }
        if let name = look.holidayName {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { parts.append(name) }
            parts.append(String(localized: "Holiday"))
        }
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}
