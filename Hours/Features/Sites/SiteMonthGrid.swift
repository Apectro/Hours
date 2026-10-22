import SwiftUI

/// A site's month, drawn the way the calendar draws yours: the same circle
/// around the day's number, the same ring for today, the same rounded cells.
/// What differs is what a cell says — whether the day was written up on this
/// site, and how many people were there — because that is the question a
/// supervisor scans a site's month for.
///
/// Weekends are always shown, whatever the calendar's own setting: a
/// Saturday on site is ordinary, and a hidden column would hide written days.
struct SiteMonthGrid: View {
    let layout: MonthLayout
    /// People present on each written day, by date key. A key that is missing
    /// is a day with nothing stored for this site.
    let presentCounts: [Int: Int]
    let selectedDate: CalendarDate
    let today: CalendarDate
    let calendar: Calendar
    let formatting: CalendarFormatting
    let onSelect: (CalendarDate) -> Void
    let onStep: (Int) -> Void
    /// Date keys with a site diary or diary photo.
    var diaryDateKeys: Set<Int> = []
    /// Date keys the weather stopped work on.
    var badWeatherDateKeys: Set<Int> = []
    /// Date keys of public holidays off, which are never unwritten.
    var holidayDateKeys: Set<Int> = []
    /// Date keys with extra work written down.
    var extraWorkDateKeys: Set<Int> = []

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.tiny), count: max(layout.columnCount, 1))
    }

    var body: some View {
        VStack(spacing: Metrics.small) {
            monthHeader

            WeekdayHeader(weekdays: layout.weekdays, formatting: formatting)

            LazyVGrid(columns: columns, spacing: Metrics.tiny) {
                ForEach(layout.days, id: \.key) { date in
                    SiteDayCell(
                        date: date,
                        presentCount: presentCounts[date.key],
                        isInMonth: layout.isInMonth(date),
                        isSelected: date == selectedDate,
                        isToday: date == today,
                        isUnwritten: isUnwritten(date),
                        hasDiary: diaryDateKeys.contains(date.key),
                        isBadWeather: badWeatherDateKeys.contains(date.key),
                        hasExtraWork: extraWorkDateKeys.contains(date.key)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(date) }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: Metrics.small) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous month")
            .accessibilityIdentifier("site-month-previous")

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
            .accessibilityLabel("Next month")
            .accessibilityIdentifier("site-month-next")
        }
        .buttonStyle(.borderless)
    }

    /// See `SiteUnwrittenDay`: a past weekday of the month with nothing
    /// written, and not a public holiday.
    private func isUnwritten(_ date: CalendarDate) -> Bool {
        SiteUnwrittenDay.isUnwritten(
            date,
            isInMonth: layout.isInMonth(date),
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

    let date: CalendarDate
    let presentCount: Int?
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isUnwritten: Bool
    var hasDiary: Bool = false
    var isBadWeather: Bool = false
    var hasExtraWork: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            DayNumberCircle(day: date.day, isSelected: isSelected, isToday: isToday)
            detailLabel
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

    @ViewBuilder
    private var detailLabel: some View {
        HStack(spacing: 2) {
            if isBadWeather {
                // Rained off: a cloud where the dot would be.
                Image(systemName: "cloud.rain.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.hoursNegative)
            } else if let presentCount, presentCount > 0 {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
            }
            if let presentCount, presentCount > 0 {
                Text(verbatim: "\(presentCount)")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if hasDiary {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if hasExtraWork {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if !isBadWeather && (presentCount ?? 0) == 0 && !hasDiary && !hasExtraWork {
                Color.clear.frame(width: 5, height: 5)
            }
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
        if isBadWeather { parts.append(String(localized: "Rained off")) }
        if hasDiary { parts.append(String(localized: "Site diary")) }
        if hasExtraWork { parts.append(String(localized: "Extra work")) }
        if isToday { parts.append(String(localized: "Today")) }
        return parts.joined(separator: ", ")
    }
}
