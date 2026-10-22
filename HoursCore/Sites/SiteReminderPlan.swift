import Foundation

/// Which upcoming evenings should nudge the supervisor to record a site day.
///
/// Decided per site, not across all sites: a site that is usually worked on
/// Tuesdays expects a Tuesday entry even when another site was already
/// recorded that day. Only weekdays a site was actually worked in the recent
/// past count, so a site that stopped being visited stops being nagged about.
enum SiteReminderPlan {
    /// Dates from `today` up to (not including) `today + daysAhead` that some
    /// site is expected on but has no site day for. Sorted, without duplicates.
    /// The look-back window is the `lookBackDays` days before `today`; today
    /// itself is not history, it is the thing being checked. Public holidays
    /// (`holidays`, date keys) are never a missing site day.
    static func dates(
        siteDays: [SiteDay],
        today: CalendarDate,
        calendar: Calendar,
        lookBackDays: Int = 14,
        daysAhead: Int = 7,
        holidays: Set<Int> = []
    ) -> [CalendarDate] {
        guard lookBackDays > 0, daysAhead > 0 else { return [] }
        let windowStart = today.adding(days: -lookBackDays, in: calendar)

        var weekdaysBySite: [UUID: Set<Int>] = [:]
        var recorded: [UUID: Set<CalendarDate>] = [:]
        for siteDay in siteDays {
            recorded[siteDay.siteID, default: []].insert(siteDay.date)
            if siteDay.date >= windowStart && siteDay.date < today {
                weekdaysBySite[siteDay.siteID, default: []].insert(siteDay.date.weekday(in: calendar))
            }
        }

        var result: [CalendarDate] = []
        for offset in 0..<daysAhead {
            let date = today.adding(days: offset, in: calendar)
            if holidays.contains(date.key) { continue }
            let weekday = date.weekday(in: calendar)
            let missing = weekdaysBySite.contains { siteID, weekdays in
                weekdays.contains(weekday) && !(recorded[siteID]?.contains(date) ?? false)
            }
            if missing { result.append(date) }
        }
        return result
    }
}
