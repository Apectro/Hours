import Foundation
import SwiftData

/// Plans and schedules the evening site reminders.
///
/// One place, because two callers need the identical result: the app coming to
/// the front, and the settings screen after the toggle or the time changes.
/// Were they separate, a time picker would move nothing until the next return
/// to the app.
enum SiteReminderRefresher {
    /// How much history decides which weekdays a site is normally worked.
    static let lookBackDays = 14

    @MainActor
    static func refresh(
        context: ModelContext,
        preferences: ReminderPreferences,
        calendar: Calendar
    ) async {
        let scheduler = ReminderScheduler()
        guard preferences.siteRemindersEnabled else {
            await scheduler.cancelSiteReminders()
            return
        }

        let today = CalendarDate.today(in: calendar)
        let window = CalendarDateRange(
            start: today.adding(days: -lookBackDays, in: calendar),
            end: today
        )
        let siteDays = SiteRepository(context: context).siteDays(siteID: nil, in: window)
        let dates = SiteReminderPlan.dates(
            siteDays: siteDays,
            today: today,
            calendar: calendar,
            lookBackDays: lookBackDays
        )
        await scheduler.scheduleSiteReminders(
            dates: dates,
            time: preferences.siteReminderTime,
            calendar: calendar
        )
    }
}
