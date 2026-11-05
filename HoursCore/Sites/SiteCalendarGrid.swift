import Foundation

/// A site's month in the Today tab's tile look (`CalendarMonthGrid`): what
/// each drawn day is, what goes under it, and each row's week total.
///
/// The grid shows the neighbouring months' days in its first and last rows,
/// so their statuses are worked out too, each month by its own rule
/// (`SiteDayStatus.month` with that month's `SiteMonthOverview.crew`) from
/// that month's days and the look-back before it: the shown month reads
/// exactly as it does on its own, and so does the month either side.
enum SiteCalendarGrid {
    /// Every day the grid needs: the look-back before the first month it
    /// touches (`SiteWorkDays.lookBackDays`) to the end of the last row's
    /// week, for its total.
    static func fetchRange(of layout: MonthLayout, calendar: Calendar) -> CalendarDateRange {
        let span = CalendarWeekTotals.span(of: layout, calendar: calendar)
        let firstMonth = min(span.start.yearMonth, layout.month)
        return CalendarDateRange(
            start: firstMonth.firstDay.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: max(span.end, layout.month.range(in: calendar).end)
        )
    }

    /// Every day of the layout with its status.
    ///
    /// - `siteDays`: every site's days over `fetchRange(of:calendar:)`.
    /// - `members`: every site's crew, hidden people too
    ///   (`SiteMonthOverview.crew`).
    static func statuses(
        layout: MonthLayout,
        siteID: UUID,
        siteDays: [SiteDay],
        members: [CrewMember],
        setup: SiteSetup,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int>
    ) -> [CalendarDate: SiteDayStatus] {
        var months: [YearMonth] = []
        for date in layout.days where !months.contains(date.yearMonth) {
            months.append(date.yearMonth)
        }
        let drawn = Set(layout.days)

        var result: [CalendarDate: SiteDayStatus] = [:]
        for month in months {
            let range = month.range(in: calendar)
            let from = range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar)
            let days = siteDays.filter { $0.date >= from && $0.date <= range.end }
            let check = SiteMonthOverview.crew(
                siteID: siteID, members: members, siteDays: days, month: month, calendar: calendar
            )
            let statuses = SiteDayStatus.month(
                month, siteID: siteID, siteDays: days, setup: setup, check: check,
                today: today, calendar: calendar, holidays: holidays
            )
            for (date, status) in statuses where drawn.contains(date) {
                result[date] = status
            }
        }
        return result
    }

    /// How many people are ticked present on each of the site's days, you
    /// included when you are: the "• 5" under a written day.
    static func people(siteID: UUID, siteDays: [SiteDay]) -> [CalendarDate: Int] {
        var result: [CalendarDate: Int] = [:]
        for day in siteDays where day.siteID == siteID {
            result[day.date] = day.present.count
        }
        return result
    }

    /// The crew's minutes on this site in each row's whole week, in row
    /// order (`CalendarWeekTotals.weeks`): hidden weekends and the
    /// neighbouring months' days count.
    static func weekMinutes(
        of layout: MonthLayout,
        siteID: UUID,
        siteDays: [SiteDay],
        calculator: SiteDayCalculator,
        calendar: Calendar
    ) -> [Int] {
        let ours = siteDays.filter { $0.siteID == siteID }
        let minutes = ours.map { (date: $0.date, minutes: calculator.compute($0).crewTotalMinutes) }
        return CalendarWeekTotals.weeks(of: layout, calendar: calendar).map { week in
            minutes.reduce(0) { total, day in week.contains(day.date) ? total + day.minutes : total }
        }
    }

    /// Whether a day of the site sits on a tile: written, partly written,
    /// or a work day nobody wrote. Today always does; that is the view's.
    static func hasTile(_ status: SiteDayStatus) -> Bool {
        switch status {
        case .written, .partly, .missing: return true
        case .dayOff, .future, .noWork, .elsewhere: return false
        }
    }

    /// Which rows have no tile at all, today's included: drawn shorter, as
    /// on Today (`CalendarWeekTotals.shortRows`).
    static func shortRows(
        of layout: MonthLayout,
        statuses: [CalendarDate: SiteDayStatus],
        today: CalendarDate
    ) -> [Bool] {
        CalendarWeekTotals.rows(of: layout).map { row in
            !row.contains { date in
                date == today || statuses[date].map(hasTile) == true
            }
        }
    }
}
