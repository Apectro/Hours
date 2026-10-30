import SwiftUI

/// A site's month, drawn the way the calendar draws yours: the same circle
/// around the day's number, the same ring for today, the same rounded cells.
/// What differs is what a cell says — whether the day was written up on this
/// site, and how many people were there — because that is the question a
/// supervisor scans a site's month for.
///
/// Folded to the selected day's week by default, so the day's crew sits near
/// the top of the screen where it is ticked; "Show whole month" opens the
/// full grid in place. The arrows step a week while folded and a month while
/// open, and the screen moves the selection with them.
///
/// Weekends are always shown, whatever the calendar's own setting: a
/// Saturday on site is ordinary, and a hidden column would hide written days.
struct SiteMonthGrid: View {
    /// The whole month, which is what the open grid draws.
    let layout: MonthLayout
    /// The selected day's week, which is what the folded grid draws.
    let weekLayout: MonthLayout
    let isExpanded: Bool
    /// People present on each written day, by date key. A key that is missing
    /// is a day with nothing stored for this site.
    let presentCounts: [Int: Int]
    let selectedDate: CalendarDate
    let today: CalendarDate
    let calendar: Calendar
    let formatting: CalendarFormatting
    let onSelect: (CalendarDate) -> Void
    /// -1 or +1: a week back or on while folded, a month while open.
    let onStep: (Int) -> Void
    let onToggleExpanded: () -> Void
    /// Date keys with a site diary or diary photo.
    var diaryDateKeys: Set<Int> = []
    /// Date keys the weather stopped work on.
    var badWeatherDateKeys: Set<Int> = []
    /// Date keys of public holidays off, which are never unwritten.
    var holidayDateKeys: Set<Int> = []
    /// Date keys with extra work written down.
    var extraWorkDateKeys: Set<Int> = []
    /// Days some of the crew were away for a reason, by date key.
    var awayMarks: [Int: SiteAwayMark] = [:]

    private var shown: MonthLayout { isExpanded ? layout : weekLayout }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.tiny), count: max(shown.columnCount, 1))
    }

    var body: some View {
        VStack(spacing: Metrics.small) {
            header

            WeekdayHeader(weekdays: shown.weekdays, formatting: formatting)

            LazyVGrid(columns: columns, spacing: Metrics.tiny) {
                ForEach(shown.days, id: \.key) { date in
                    SiteDayCell(
                        date: date,
                        presentCount: presentCounts[date.key],
                        // A folded week shows every one of its days at full
                        // strength, borrowed or not: there is no month around
                        // it to set them apart from.
                        isInMonth: isExpanded ? layout.isInMonth(date) : true,
                        isSelected: date == selectedDate,
                        isToday: date == today,
                        isUnwritten: isUnwritten(date),
                        hasDiary: diaryDateKeys.contains(date.key),
                        isBadWeather: badWeatherDateKeys.contains(date.key),
                        hasExtraWork: extraWorkDateKeys.contains(date.key),
                        away: awayMarks[date.key]
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(date) }
                }
            }

            Button(action: onToggleExpanded) {
                Label(
                    isExpanded ? String(localized: "Show one week") : String(localized: "Show whole month"),
                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("site-month-toggle")
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.small) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(isExpanded ? String(localized: "Previous month") : String(localized: "Previous week"))
            .accessibilityIdentifier(isExpanded ? "site-month-previous" : "site-week-previous")

            Spacer(minLength: 0)

            Text(formatting.monthTitle(layout.month))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(isExpanded ? String(localized: "Next month") : String(localized: "Next week"))
            .accessibilityIdentifier(isExpanded ? "site-month-next" : "site-week-next")
        }
        .buttonStyle(.borderless)
    }

/// See `SiteUnwrittenDay`: a past weekday of the month with nothing
    /// written, and not a public holiday.
    private func isUnwritten(_ date: CalendarDate) -> Bool {
        SiteUnwrittenDay.isUnwritten(
            date,
            isInMonth: isExpanded ? layout.isInMonth(date) : true,
            today: today,
            isWritten: presentCounts[date.key] != nil,
            calendar: calendar,
            holidays: holidayDateKeys
        )
    }
}

/// One day of a site's month.
struct SiteDayCell: View {
    // Grows with the user's text size, as the calendar's cell does. Not
    // `private`: a private stored property makes the memberwise initializer
    // private too.
    @ScaledMetric(relativeTo: .subheadline) var cellHeight: CGFloat = Metrics.dayCellHeight
    @ScaledMetric(relativeTo: .caption2) var dotDiameter: CGFloat = 5
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let date: CalendarDate
    let presentCount: Int?
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isUnwritten: Bool
    var hasDiary: Bool = false
    var isBadWeather: Bool = false
    var hasExtraWork: Bool = false
    var away: SiteAwayMark?

    var body: some View {
        VStack(spacing: 2) {
            DayNumberCircle(day: date.day, isSelected: isSelected, isToday: isToday)
                // Large, but no wider than a seventh of the screen allows.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            if dynamicTypeSize.isAccessibilitySize {
                compactMark
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                detailLabel
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background {
            DayCellBackground(
                wash: presentCount != nil ? Color.accentColor.opacity(0.12) : .clear,
                isMissing: isUnwritten
            )
        }
        .opacity(isInMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The label is a translated sentence; the date key is not.
        .accessibilityIdentifier("site-day-\(date.key)")
    }

    /// At most two marks beside the count, at a size that scales with the
    /// text: the rain cloud stands in for the dot, and a diary and extra work
    /// on the same day share one mark. VoiceOver names each of them.
    @ViewBuilder
    private var detailLabel: some View {
        HStack(spacing: 2) {
            if isBadWeather {
                Image(systemName: "cloud.rain.fill")
                    .font(.caption2.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(Color.hoursNegative)
            } else if let away {
                // Half the crew's colour, half the reason's: fewer people
                // than usual. Nobody here at all is the reason's alone.
                Circle()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: (presentCount ?? 0) > 0 ? Color.accentColor : away.color, location: 0.5),
                            .init(color: away.color, location: 0.5),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: splitDotDiameter, height: splitDotDiameter)
            } else if let presentCount, presentCount > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: dotDiameter, height: dotDiameter)
            }
            if let presentCount, presentCount > 0 {
                Text(verbatim: "\(presentCount)")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let noteMark {
                Image(systemName: noteMark)
                    .font(.caption2.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            if !isBadWeather && (presentCount ?? 0) == 0 && away == nil && noteMark == nil {
                Color.clear.frame(width: dotDiameter, height: dotDiameter)
            }
        }
        .lineLimit(1)
    }

    /// At accessibility text sizes a seventh of the screen holds one mark, not
    /// three: the crew count when people were there (orange on a rain day, the
    /// leading reason's colour when some were away), otherwise the rain cloud,
    /// otherwise a dot in the reason's colour when everyone was away, otherwise
    /// one dot for a diary or extra work. VoiceOver still names everything.
    @ViewBuilder
    private var compactMark: some View {
        if let presentCount, presentCount > 0 {
            Text(verbatim: "\(presentCount)")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isBadWeather ? Color.hoursNegative : away?.color ?? Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else if isBadWeather {
            Image(systemName: "cloud.rain.fill")
                .font(.caption2.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(Color.hoursNegative)
        } else if let away {
            Circle()
                .fill(away.color)
                .frame(width: compactDotDiameter, height: compactDotDiameter)
        } else if noteMark != nil {
            Circle()
                .fill(Color.secondary)
                .frame(width: compactDotDiameter, height: compactDotDiameter)
        } else {
            Color.clear.frame(width: compactDotDiameter, height: compactDotDiameter)
        }
    }

    /// `dotDiameter` scales with the cell's own (accessibility) size; the
    /// compact mark is capped, so its dot is too.
    private var compactDotDiameter: CGFloat {
        min(dotDiameter, 8)
    }

    /// Big enough for its two halves to read as two colours.
    private var splitDotDiameter: CGFloat { dotDiameter * 1.4 }

    /// The diary's book, the extra work's wrench, or one ellipsis for both.
    private var noteMark: String? {
        switch (hasDiary, hasExtraWork) {
        case (true, true): return "ellipsis"
        case (true, false): return "text.book.closed.fill"
        case (false, true): return "wrench.and.screwdriver.fill"
        case (false, false): return nil
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = ["\(date.day)"]
        if let presentCount {
            parts.append(String(localized: "Written"))
            if presentCount > 0 {
                parts.append(String(inflected: "^[\(presentCount) person](inflect: true)"))
            }
        } else if isUnwritten {
            parts.append(String(localized: "Not written"))
        }
        if let away {
            parts.append(String(localized: "Away: \(away.count)", comment: "VoiceOver, a site's month: how many of the crew were away for a reason"))
            parts.append(away.title)
        }
        if isBadWeather { parts.append(String(localized: "Bad weather")) }
        if hasDiary { parts.append(String(localized: "Site diary")) }
        if hasExtraWork { parts.append(String(localized: "Extra work")) }
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}

/// Some of a site's crew were away on a day: how many, and the colour and
/// name of the reason that leads (`SiteDay.leadingAwayReason`).
struct SiteAwayMark: Equatable {
    let count: Int
    let color: Color
    let title: String
}

// MARK: - A site's month by status (1.2, mockup Sites)

extension SiteDayStatus {
    /// The fill for this status in the card's strip and the site's month:
    /// green written, orange partly, red missing, grey nothing expected.
    var fill: Color {
        switch self {
        case .written: return .hoursDone
        case .partly: return .hoursAttentionFill
        case .missing: return .hoursMissingFill
        case .dayOff: return Color(uiColor: .systemGray5)
        case .future: return Color(uiColor: .systemGray5)
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

/// A site's month on its own page (1.2, mockup Sites): every day coloured by
/// `SiteDayStatus` — green written, orange outlined partly, red dashed not
/// written, grey a day off, outlined grey still to come — with today ringed
/// in the accent. A day is a link to that day on the site.
///
/// Weekends are always shown, as in `SiteMonthGrid`.
struct SiteStatusMonthGrid: View {
    let month: YearMonth
    let statuses: [CalendarDate: SiteDayStatus]
    let today: CalendarDate
    let calendar: Calendar
    let formatting: CalendarFormatting
    /// Where a day leads: the day on the site.
    let route: (CalendarDate) -> SiteRoute

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.tiny), count: 7)
    }

    /// The month's days, after blanks for the weekdays before the 1st.
    private var cells: [CalendarDate?] {
        let days = month.range(in: calendar).days(in: calendar)
        guard let first = days.first else { return [] }
        let order = formatting.orderedWeekdayNumbers
        let lead = order.firstIndex(of: first.weekday(in: calendar)) ?? 0
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    var body: some View {
        VStack(spacing: Metrics.small) {
            HStack(spacing: Metrics.tiny) {
                ForEach(formatting.orderedWeekdayNumbers, id: \.self) { weekday in
                    Text(verbatim: formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.hoursSecondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: columns, spacing: Metrics.tiny) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        NavigationLink(value: route(date)) {
                            SiteStatusDayCell(date: date, status: statuses[date] ?? .dayOff, isToday: date == today)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("site-overview-day-\(date.key)")
                    } else {
                        Color.clear.frame(height: 1).accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// One day of `SiteStatusMonthGrid`.
private struct SiteStatusDayCell: View {
    let date: CalendarDate
    let status: SiteDayStatus
    let isToday: Bool

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 36
    @Environment(\.highContrast) private var highContrast

    private let corner: CGFloat = 8

    var body: some View {
        Text(verbatim: "\(date.day)")
            .font(.system(.caption, design: .rounded, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(background)
            .overlay(border)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    private var foreground: Color {
        switch status {
        case .written: return .white
        case .partly: return .hoursAttention
        case .missing: return .hoursMissing
        case .dayOff, .future: return highContrast ? Color.primary.opacity(0.85) : .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        switch status {
        case .written: shape.fill(Color.hoursDone)
        case .partly: shape.fill(Color.hoursAttentionFill.opacity(0.18))
        case .missing: shape.fill(Color.hoursSurface)
        case .dayOff: shape.fill(Color(uiColor: .systemGray5))
        case .future: shape.fill(Color.hoursSurface)
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        switch status {
        case .partly: shape.strokeBorder(Color.hoursAttentionFill, lineWidth: 1.5)
        case .missing: shape.strokeBorder(Color.hoursMissing, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        case .future: shape.strokeBorder(.hoursHairlineStyle, lineWidth: 1)
        case .written, .dayOff: EmptyView()
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(date.day)", status.title]
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}

/// What the colours of a site's month mean.
struct SiteStatusLegend: View {
    private let items: [SiteDayStatus] = [.written, .partly, .missing, .dayOff]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.medium) { entries }
            VStack(alignment: .leading, spacing: Metrics.tiny) { entries }
        }
        .font(.caption)
        .foregroundStyle(.hoursSecondaryText)
        .accessibilityElement(children: .combine)
    }

    private var entries: some View {
        ForEach(items, id: \.self) { status in
            HStack(spacing: Metrics.tiny) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(status.fill)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(verbatim: status.title)
                    .lineLimit(1)
            }
        }
    }
}
