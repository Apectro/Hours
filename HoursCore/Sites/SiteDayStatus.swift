import Foundation

/// How one day of a site reads in its month: the site's half of "not
/// written", beside `MissingDays` for your own days.
///
/// Whether a day is expected is the evening reminder's rule
/// (`SiteWorkDays.expects`): the site's work days when they are set, the
/// weekdays it was worked lately when not, and never a public holiday.
/// Whether it is written is the reminder's rule too
/// (`SiteReminderPlan.isWritten`): any site day stored for it. Switching the
/// evening reminder off silences the nudge, not the month: its unwritten
/// days still show.
enum SiteDayStatus: Hashable, Sendable {
    /// Written, with everyone on the crew either ticked or given a reason.
    case written
    /// Written, but someone on the crew is neither ticked present nor given
    /// a reason for being away.
    case partly
    /// A work day of the site, before today, with no site day.
    case missing
    /// Not a work day of the site, or a public holiday, and nothing written.
    case dayOff
    /// A work day from today on with nothing written yet: today is not over.
    case future
    /// Recorded as "no work" (`SiteDay.isNoWorkDay`): nobody worked here,
    /// for a reason. Drawn like a day off, with the reason's word.
    case noWork
    /// A work day with nothing written, on which everyone expected here was
    /// on another of your sites (`SiteCrewCheck.isAllElsewhere`): not
    /// missing, drawn like a day off, and no reminder asks about it.
    case elsewhere

    /// One day's status.
    ///
    /// `crew` is the people expected on that day
    /// (`SiteCrewCheck.expected(on:)`): anyone in it with no entry and no
    /// reason makes a written day `.partly`.
    /// `holidays` are date keys of public holidays. `crewElsewhere`: every
    /// person expected that day was on another of your sites.
    static func of(
        siteID: UUID,
        on date: CalendarDate,
        siteDays: [SiteDay],
        setup: SiteSetup,
        crew: Set<UUID>,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int> = [],
        crewElsewhere: Bool = false
    ) -> SiteDayStatus {
        if let day = siteDays.first(where: { $0.siteID == siteID && $0.date == date }) {
            if day.isNoWorkDay { return .noWork }
            let unaccounted = crew.contains { day.attendance(for: $0) == nil && day.absenceReason(for: $0) == nil }
            return unaccounted ? .partly : .written
        }
        let expected = SiteWorkDays.expects(
            siteID, on: date, setup: setup, siteDays: siteDays, calendar: calendar, holidays: holidays, today: today
        )
        guard expected else { return .dayOff }
        if crewElsewhere { return .elsewhere }
        return date < today ? .missing : .future
    }

    /// Every day of `month`, with its status, each written day checked
    /// against the same `crew` whatever its date.
    static func month(
        _ month: YearMonth,
        siteID: UUID,
        siteDays: [SiteDay],
        setup: SiteSetup,
        crew: Set<UUID>,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int> = []
    ) -> [CalendarDate: SiteDayStatus] {
        self.month(
            month, siteID: siteID, siteDays: siteDays, setup: setup, check: SiteCrewCheck(always: crew),
            today: today, calendar: calendar, holidays: holidays
        )
    }

    /// Every day of `month`, with its status, each written day checked
    /// against who was expected on it (`SiteMonthOverview.crew`): people
    /// count from the day they joined, and not on a day another site has
    /// them.
    static func month(
        _ month: YearMonth,
        siteID: UUID,
        siteDays: [SiteDay],
        setup: SiteSetup,
        check: SiteCrewCheck,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int> = []
    ) -> [CalendarDate: SiteDayStatus] {
        let ours = siteDays.filter { $0.siteID == siteID }
        var result: [CalendarDate: SiteDayStatus] = [:]
        for date in month.range(in: calendar).days(in: calendar) {
            result[date] = of(
                siteID: siteID, on: date, siteDays: ours, setup: setup, crew: check.expected(on: date),
                today: today, calendar: calendar, holidays: holidays,
                crewElsewhere: check.isAllElsewhere(on: date)
            )
        }
        return result
    }

    /// How many of `statuses` are missing.
    static func missingCount(in statuses: [CalendarDate: SiteDayStatus]) -> Int {
        statuses.values.filter { $0 == .missing }.count
    }

    /// The missing days of `statuses`, in order.
    static func missingDays(in statuses: [CalendarDate: SiteDayStatus]) -> [CalendarDate] {
        statuses.filter { $0.value == .missing }.keys.sorted()
    }
}
