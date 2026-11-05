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
    /// person expected that day was on another of your sites. `active`:
    /// the days the site was there to be worked (`SiteActiveDays`); a day
    /// outside them with nothing written is a day off.
    static func of(
        siteID: UUID,
        on date: CalendarDate,
        siteDays: [SiteDay],
        setup: SiteSetup,
        crew: Set<UUID>,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int> = [],
        crewElsewhere: Bool = false,
        active: SiteActiveDays = .always
    ) -> SiteDayStatus {
        if let day = siteDays.first(where: { $0.siteID == siteID && $0.date == date }) {
            if day.isNoWorkDay { return .noWork }
            let unaccounted = crew.contains { day.attendance(for: $0) == nil && day.absenceReason(for: $0) == nil }
            return unaccounted ? .partly : .written
        }
        guard active.contains(date) else { return .dayOff }
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
        holidays: Set<Int> = [],
        active: SiteActiveDays = .always
    ) -> [CalendarDate: SiteDayStatus] {
        self.month(
            month, siteID: siteID, siteDays: siteDays, setup: setup, check: SiteCrewCheck(always: crew),
            today: today, calendar: calendar, holidays: holidays, active: active
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
        holidays: Set<Int> = [],
        active: SiteActiveDays = .always
    ) -> [CalendarDate: SiteDayStatus] {
        let ours = siteDays.filter { $0.siteID == siteID }
        var result: [CalendarDate: SiteDayStatus] = [:]
        for date in month.range(in: calendar).days(in: calendar) {
            result[date] = of(
                siteID: siteID, on: date, siteDays: ours, setup: setup, crew: check.expected(on: date),
                today: today, calendar: calendar, holidays: holidays,
                crewElsewhere: check.isAllElsewhere(on: date),
                active: active
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

/// The days a site was there to be worked, for its month: from its first
/// day written, and for an archived site up to its last. A day outside them
/// with nothing on it is not missing (a site set up mid-month, with work
/// days Monday to Friday, is not red before it began) and not still to
/// come (an archived site is done).
struct SiteActiveDays: Hashable, Sendable {
    /// The first day; nil for no bound.
    var since: CalendarDate?
    /// The last day, inclusive; nil for no bound.
    var until: CalendarDate?

    /// Every day: no bound either side.
    static let always = SiteActiveDays()

    /// - `firstWritten`, `lastWritten`: the site's first and last days
    ///   written, of any kind, nil when it has none.
    ///
    /// The days start at the first day written, or today for a site with
    /// none yet (nothing before today is missing then, and its days from
    /// today on are still to come), and never after today, so a day written
    /// ahead leaves the days up to it as they were. An archived site's days
    /// end at its last day written, or before today with none.
    static func of(
        firstWritten: CalendarDate?,
        lastWritten: CalendarDate?,
        isArchived: Bool,
        today: CalendarDate,
        calendar: Calendar
    ) -> SiteActiveDays {
        let since = min(firstWritten ?? today, today)
        guard isArchived else { return SiteActiveDays(since: since) }
        return SiteActiveDays(since: since, until: lastWritten ?? today.adding(days: -1, in: calendar))
    }

    func contains(_ date: CalendarDate) -> Bool {
        if let since, date < since { return false }
        if let until, date > until { return false }
        return true
    }
}
