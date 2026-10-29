import Foundation

/// One note on the 1st: this site's sheet for the month just ended is ready
/// to hand to the director.
struct MonthlySheetReminder: Hashable, Sendable {
    let siteID: UUID
    let siteName: String
    /// The month the sheet covers, which is the one before `date`.
    let month: YearMonth
    /// Always the 1st of a month.
    let date: CalendarDate
}

/// Which sites get a "send it to your director" note on the next 1st.
///
/// A supervisor hands each site's monthly sheet over at the start of the next
/// month, so the note comes on the 1st and opens that site's export on the
/// month just ended. Only the next 1st is ever planned: the month after that
/// depends on days not written yet, and the plan is redone whenever a site day
/// changes and every time the app is opened.
enum MonthlySheetReminderPlan {
    /// The month the next note is about. On the 1st before the time it is
    /// still last month's; from then on it is this month's, due next 1st.
    static func coveredMonth(today: CalendarDate, now: TimeOfDay, time: TimeOfDay) -> YearMonth {
        let thisMonth = today.yearMonth
        if today.day == 1 && now < time {
            return thisMonth.adding(months: -1)
        }
        return thisMonth
    }

    /// One note per active site with at least one day written in the covered
    /// month, in the order the sites are given. A site with nothing that
    /// month has no sheet worth sending, and an archived one is finished. A
    /// site with the note switched off in its settings (`silenced`, 1.2)
    /// gets none.
    static func reminders(
        sites: [Site],
        siteDays: [SiteDay],
        today: CalendarDate,
        now: TimeOfDay,
        time: TimeOfDay,
        silenced: Set<UUID> = []
    ) -> [MonthlySheetReminder] {
        let month = coveredMonth(today: today, now: now, time: time)
        let worked = Set(siteDays.filter { month.contains($0.date) }.map(\.siteID))
        let date = month.adding(months: 1).firstDay
        return sites
            .filter { !$0.isArchived && worked.contains($0.id) && !silenced.contains($0.id) }
            .map { MonthlySheetReminder(siteID: $0.id, siteName: $0.name, month: month, date: date) }
    }
}
