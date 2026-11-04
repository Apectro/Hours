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
        case .dayOff, .future: return nil
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
        }
    }
}

/// A site's month on its own page, in the Today tab's look
/// (`CalendarTileGrid`): a written day on an accent tile with "• 5" under
/// the date, the people on it (you included when listed), orange while
/// someone on the crew is neither ticked nor given a reason; a work day
/// before today nobody wrote on a tile with a red dot; days off and days
/// still to come without a tile, the date in the tertiary colour; today's
/// tile filled. The first and last rows show the neighbouring months' days,
/// faded. The eighth column is the crew's hours on the site in each row's
/// whole week. A day opens that day on the site.
struct SiteMonthCalendar: View {
    let layout: MonthLayout
    /// Every drawn day (`SiteCalendarGrid.statuses`).
    let statuses: [CalendarDate: SiteDayStatus]
    /// People present on each written day (`SiteCalendarGrid.people`).
    let people: [CalendarDate: Int]
    /// One per row, in minutes (`SiteCalendarGrid.weekMinutes`).
    let weekTotals: [Int]
    let today: CalendarDate
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
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
            shortRows: SiteCalendarGrid.shortRows(of: layout, statuses: statuses, today: today)
        ) { date, height in
            Button {
                onSelect(date)
            } label: {
                SiteDayTile(
                    date: date,
                    status: statuses[date] ?? .dayOff,
                    people: people[date] ?? 0,
                    isToday: date == today,
                    isOutsideMonth: !layout.isInMonth(date),
                    spokenDay: formatting.spokenDay(date, in: layout),
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
    let status: SiteDayStatus
    let people: Int
    let isToday: Bool
    let isOutsideMonth: Bool
    /// "1", or "31 October" for a neighbouring month's day
    /// (`CalendarFormatting.spokenDay`).
    let spokenDay: String
    let height: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 6

    var body: some View {
        CalendarTileFace(
            day: date.day,
            isToday: isToday,
            fill: fill,
            numberColor: numberColor,
            isBold: isToday || hasTile,
            isOutsideMonth: isOutsideMonth,
            height: height,
            accessibilityLabel: accessibilityLabel
        ) {
            under
        }
    }

    private var hasTile: Bool { SiteCalendarGrid.hasTile(status) }

    private var fill: Color? {
        if isToday { return .accentColor }
        return hasTile ? Color.accentColor.opacity(0.14) : nil
    }

    private var numberColor: Color {
        if isToday { return .white }
        return hasTile ? .primary : Color(uiColor: .tertiaryLabel)
    }

    /// "• 5" on a written day, orange while partly written; a red dot on a
    /// day nobody wrote; nothing on a day off or a day to come.
    @ViewBuilder
    private var under: some View {
        switch status {
        case .written, .partly:
            if people > 0 {
                Text(verbatim: "• \(people)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(peopleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Color.clear
            }
        case .missing where !isToday:
            Circle()
                .fill(Color.hoursMissingFill)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
        default:
            Color.clear
        }
    }

    private var peopleColor: Color {
        if isToday { return .white }
        return status == .partly ? .hoursAttention : .accentColor
    }

    private var accessibilityLabel: String {
        var parts = [spokenDay, status.title]
        if people > 0, status == .written || status == .partly {
            parts.append(String(inflected: "^[\(people) person](inflect: true)"))
        }
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}
