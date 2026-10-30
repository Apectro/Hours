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

/// A site's month on its own page, in the one calendar look of the app: no
/// boxes, the weekday letters, a hairline between weeks, each date in a
/// circle (today filled in the accent, days off in the tertiary colour) and
/// a small dot under it for how the day stands (`SiteDayStatus.dot`). Days
/// of other months are not shown. A day opens that day on the site.
struct SiteMonthCalendar: View {
    let month: YearMonth
    let statuses: [CalendarDate: SiteDayStatus]
    let today: CalendarDate
    let calendar: Calendar
    let formatting: CalendarFormatting
    /// Opens a day on the site. Buttons rather than links: the month is one
    /// row of a List, where links would make the whole row one.
    let onSelect: (CalendarDate) -> Void

    /// The month in weeks, nil where a week runs into another month.
    private var weeks: [[CalendarDate?]] {
        let days = month.range(in: calendar).days(in: calendar)
        guard let first = days.first else { return [] }
        let order = formatting.orderedWeekdayNumbers
        let lead = order.firstIndex(of: first.weekday(in: calendar)) ?? 0
        var cells: [CalendarDate?] = Array(repeating: nil, count: lead) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(formatting.orderedWeekdayNumbers, id: \.self) { weekday in
                    Text(verbatim: formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.hoursSecondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, Metrics.tiny)

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                Divider()
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            Button {
                                onSelect(date)
                            } label: {
                                SiteMonthDayCell(
                                    date: date,
                                    status: statuses[date] ?? .dayOff,
                                    isToday: date == today
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("site-overview-day-\(date.key)")
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 1)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

/// One day of `SiteMonthCalendar`: the date in a circle, a dot under it.
private struct SiteMonthDayCell: View {
    let date: CalendarDate
    let status: SiteDayStatus
    let isToday: Bool

    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 6

    var body: some View {
        VStack(spacing: 3) {
            Text(verbatim: "\(date.day)")
                .font(.body.weight(isToday ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(numberColor)
                .frame(width: circle, height: circle)
                .background {
                    if isToday {
                        Circle().fill(Color.accentColor)
                    }
                }
            Circle()
                .fill(status.dot ?? .clear)
                .frame(width: dotSize, height: dotSize)
        }
        .padding(.vertical, Metrics.tiny)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var numberColor: Color {
        if isToday { return .white }
        return status == .dayOff ? Color(uiColor: .tertiaryLabel) : .primary
    }

    private var accessibilityLabel: String {
        var parts = ["\(date.day)", status.title]
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}
