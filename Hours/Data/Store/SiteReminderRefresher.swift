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

    /// The refresh under way, if any. A site day is saved at every tick on
    /// its screen, so refreshes can arrive faster than the system answers;
    /// each waits for the one before it, and the last to run is the last
    /// that was asked for, planned from what is stored by then.
    @MainActor private static var inFlight: Task<Void, Never>?

    @MainActor
    static func refresh(
        context: ModelContext,
        preferences: ReminderPreferences,
        calendar: Calendar
    ) async {
        let previous = inFlight
        let task = Task { @MainActor in
            _ = await previous?.value
            await plan(context: context, preferences: preferences, calendar: calendar)
        }
        inFlight = task
        await task.value
    }

    @MainActor
    private static func plan(
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
        let settings = HoursStack.settings.settings
        // Every crew, hidden people and archived sites too: the same person
        // on two sites is matched by name (`SiteMonthOverview.crew`).
        let everySite = repository.sites(includeArchived: true)
        let members = everySite.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        // A site nobody has been to in the window has no day there to say
        // who its crew is: its last day worked says it.
        let inWindow = Set(siteDays.map(\.siteID))
        let lastDays = everySite
            .filter { !$0.isArchived && !inWindow.contains($0.id) }
            .compactMap { repository.lastSiteDay(siteID: $0.id, before: today) }
        // No evening nudge on a public holiday off.
        let ahead = CalendarDateRange(start: today, end: today.adding(days: 7, in: calendar))
        let rules = (try? context.fetch(FetchDescriptor<HolidayRecord>()))?.map(\.rule) ?? []
        let holidays = HolidayResolver(rules: rules, calendar: calendar, covering: ahead)
            .daysOffKeys(in: ahead, calendar: calendar)
        // Each active site's own say (1.2): its work days when set, whether
        // it wants the evening reminder at all, its pause, and today with
        // its whole crew on another of your sites (`SiteReminderPlan.evenings`).
        let evenings = SiteReminderPlan.evenings(
            sites: everySite,
            setup: { settings.siteSetup(for: $0) },
            members: members,
            siteDays: siteDays,
            lastDays: lastDays,
            today: today,
            calendar: calendar,
            lookBackDays: lookBackDays,
            holidays: holidays,
            // Asked "write today's hours?" on leaving: one question a day.
            askedWhenLeavingToday: ArrivalReminders.sitesAskedToWrite(on: today)
        )
        await scheduler.scheduleSiteReminders(
            evenings,
            names: Dictionary(everySite.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            time: preferences.siteReminderTime,
            calendar: calendar
        )
    }
}
