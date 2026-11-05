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
        let repository = SiteRepository(context: context)
        let siteDays = repository.siteDays(siteID: nil, in: window)
        // Each active site's own say (1.2): its work days when set, and
        // whether it wants the evening reminder at all.
        let settings = HoursStack.settings.settings
        var workDays: [UUID: Set<Int>] = [:]
        var silenced = Set<UUID>()
        var pauses: [UUID: SitePause] = [:]
        var crewElsewhere: [UUID: Set<CalendarDate>] = [:]
        // Every crew, hidden people and archived sites too: the same person
        // on two sites is matched by name (`SiteMonthOverview.crew`).
        let everySite = repository.sites(includeArchived: true)
        let members = everySite.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        for site in everySite where !site.isArchived {
            let setup = settings.siteSetup(for: site.id)
            if !setup.workDays.isEmpty { workDays[site.id] = setup.workDays }
            if !setup.eveningReminder { silenced.insert(site.id) }
            // Paused: no day expected, so no nudge.
            if let pause = setup.pause { pauses[site.id] = pause }
            // Today, with the whole crew on another of your sites: nothing
            // to write here.
            if SiteMonthOverview.isCrewElsewhere(
                siteID: site.id, on: today, members: members, siteDays: siteDays, calendar: calendar
            ) {
                crewElsewhere[site.id] = [today]
            }
        }
        // No evening nudge on a public holiday off.
        let ahead = CalendarDateRange(start: today, end: today.adding(days: 7, in: calendar))
        let rules = (try? context.fetch(FetchDescriptor<HolidayRecord>()))?.map(\.rule) ?? []
        let holidays = HolidayResolver(rules: rules, calendar: calendar, covering: ahead)
            .daysOffKeys(in: ahead, calendar: calendar)
        let dates = SiteReminderPlan.dates(
            siteDays: siteDays,
            today: today,
            calendar: calendar,
            lookBackDays: lookBackDays,
            holidays: holidays,
            // Asked "write today's hours?" on leaving: one question a day.
            askedWhenLeavingToday: ArrivalReminders.sitesAskedToWrite(on: today),
            workDays: workDays,
            silenced: silenced,
            pauses: pauses,
            crewElsewhere: crewElsewhere
        )
        await scheduler.scheduleSiteReminders(
            dates: dates,
            time: preferences.siteReminderTime,
            calendar: calendar
        )
    }
}
