import Foundation
import SwiftData

/// Plans and schedules the weekly note that finished extra work has not been
/// sent to the boss yet.
///
/// One place, as `MonthlySheetRefresher` is, because every change that can
/// alter the answer needs the identical result: the app coming to the front,
/// a job saved, ticked, deleted or sent, a site archived, and the settings
/// screen. When nothing is waiting, or the reminder is off, the note is
/// removed rather than left saying something that is no longer true.
enum ExtraWorkReminderRefresher {
    @MainActor
    static func refresh(context: ModelContext, settingsStore: SettingsStore) async {
        let preferences = settingsStore.settings.reminders
        let scheduler = ReminderScheduler()
        guard preferences.unsentWorkEnabled else {
            scheduler.cancelUnsentWorkReminder()
            return
        }

        let sites = SiteRepository(context: context).sites(includeArchived: false)
        let repository = ExtraWorkRepository(context: context)
        let jobs = sites.flatMap { repository.jobs(siteID: $0.id) }
        await scheduler.scheduleUnsentWorkReminder(
            ExtraWorkReminderPlan.reminder(sites: sites, jobs: jobs),
            weekday: preferences.unsentWorkWeekday,
            time: preferences.unsentWorkTime
        )
    }
}
