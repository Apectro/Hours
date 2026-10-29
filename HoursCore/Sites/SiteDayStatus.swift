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

    /// One day's status.
    ///
    /// `crew` is the people the day screen lists for the site (its visible
    /// crew members, and `CrewMember.youID` when you are on it): anyone
    /// in it with no entry and no reason makes a written day `.partly`.
    /// `holidays` are date keys of public holidays.
    static func of(
        siteID: UUID,
        on date: CalendarDate,
        siteDays: [SiteDay],
        setup: SiteSetup,
        crew: Set<UUID>,
        today: CalendarDate,
        calendar: Calendar,
        holidays: Set<Int> = []
    ) -> SiteDayStatus {
        if let day = siteDays.first(where: { $0.siteID == siteID && $0.date == date }) {
            let unaccounted = crew.contains { day.attendance(for: $0) == nil && day.absenceReason(for: $0) == nil }
            return unaccounted ? .partly : .written
        }
        let expected = SiteWorkDays.expects(
            siteID, on: date, setup: setup, siteDays: siteDays, calendar: calendar, holidays: holidays
        )
        guard expected else { return .dayOff }
        return date < today ? .missing : .future
    }

    /// Every day of `month`, with its status.
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
        let ours = siteDays.filter { $0.siteID == siteID }
        var result: [CalendarDate: SiteDayStatus] = [:]
        for date in month.range(in: calendar).days(in: calendar) {
            result[date] = of(
                siteID: siteID, on: date, siteDays: ours, setup: setup, crew: crew,
                today: today, calendar: calendar, holidays: holidays
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
