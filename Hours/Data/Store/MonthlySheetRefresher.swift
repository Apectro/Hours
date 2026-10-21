import Foundation
import SwiftData

/// Plans and schedules the notes on the 1st that a site's sheet is ready for
/// the director.
///
/// One place for the same reason as `SiteReminderRefresher`: the app coming to
/// the front, a site day appearing or going, a site being renamed or archived,
/// and the settings screen all need the identical result.
enum MonthlySheetRefresher {
    @MainActor
    static func refresh(context: ModelContext, settingsStore: SettingsStore) async {
        let preferences = settingsStore.settings.reminders
        let scheduler = ReminderScheduler()
        guard preferences.monthlySheetEnabled else {
            await scheduler.cancelMonthlySheetReminders()
            return
        }

        let calendar = settingsStore.workCalendar
        let now = Date()
        let today = CalendarDate.today(in: calendar, now: now)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let clock = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        let month = MonthlySheetReminderPlan.coveredMonth(
            today: today,
            now: clock,
            time: preferences.monthlySheetTime
        )

        let repository = SiteRepository(context: context)
        let reminders = MonthlySheetReminderPlan.reminders(
            sites: repository.sites(includeArchived: false),
            siteDays: repository.siteDays(siteID: nil, in: month.range(in: calendar)),
            today: today,
            now: clock,
            time: preferences.monthlySheetTime
        )
        await scheduler.scheduleMonthlySheetReminders(
            reminders,
            time: preferences.monthlySheetTime,
            formatting: settingsStore.dateFormatting,
            calendar: calendar,
            now: now
        )
    }
}
