import Foundation

/// Which upcoming evenings should nudge the supervisor to record a site day.
///
/// Decided per site, not across all sites: a site that is usually worked on
/// Tuesdays expects a Tuesday entry even when another site was already
/// recorded that day. Only weekdays a site was actually worked in the recent
/// past count, so a site that stopped being visited stops being nagged about.
enum SiteReminderPlan {
    /// One evening's nudge: the day, and the sites expected on it that have
    /// no site day, so the notification can name them.
    struct Evening: Hashable, Sendable {
        var date: CalendarDate
        /// Never empty; in the order asked for (`order`), then by id.
        var siteIDs: [UUID]
    }

    /// Dates from `today` up to (not including) `today + daysAhead` that some
    /// site is expected on but has no site day for, each with the sites
    /// that are missing. Sorted by date, without duplicates.
    /// The look-back window is the `lookBackDays` days before `today`; today
    /// itself is not history, it is the thing being checked. Public holidays
    /// (`holidays`, date keys) are never a missing site day. A site the
    /// phone already asked "write today's hours?" as you left it
    /// (`askedWhenLeavingToday`) does not make today missing: one question a
    /// day about it is enough.
    ///
    /// A site with work days set (`workDays`, from `SiteSetup`, 1.2) is
    /// expected on exactly those weekdays, a new site with no days yet
    /// included; its history no longer decides. A site with the evening
    /// reminder switched off (`silenced`) is never missing, nor is a site
    /// on a day it is paused (`pauses`, from `SiteSetup`), nor on a day its
    /// whole crew was on another of your sites (`crewElsewhere`, dates by
    /// site: `SiteMonthOverview.isCrewElsewhere`).
    ///
    /// `order` is the order the sites are named in, the Sites tab's; a site
    /// not in it follows, by id, so the answer never depends on a
    /// dictionary's order.
    static func missing(
        siteDays: [SiteDay],
        today: CalendarDate,
        calendar: Calendar,
        lookBackDays: Int = 14,
        daysAhead: Int = 7,
        holidays: Set<Int> = [],
        askedWhenLeavingToday: Set<UUID> = [],
        workDays: [UUID: Set<Int>] = [:],
        silenced: Set<UUID> = [],
        pauses: [UUID: SitePause] = [:],
        crewElsewhere: [UUID: Set<CalendarDate>] = [:],
        order: [UUID] = []
    ) -> [Evening] {
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

        for (siteID, weekdays) in workDays where !weekdays.isEmpty {
            weekdaysBySite[siteID] = weekdays
        }
        for siteID in silenced {
            weekdaysBySite[siteID] = nil
        }

        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sites = weekdaysBySite.keys.sorted { a, b in
            switch (position[a], position[b]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.uuidString < b.uuidString
            }
        }

        var result: [Evening] = []
        for offset in 0..<daysAhead {
            let date = today.adding(days: offset, in: calendar)
            if holidays.contains(date.key) { continue }
            let weekday = date.weekday(in: calendar)
            let missing = sites.filter { siteID in
                if offset == 0 && askedWhenLeavingToday.contains(siteID) { return false }
                if pauses[siteID]?.contains(date) == true { return false }
                if crewElsewhere[siteID]?.contains(date) == true { return false }
                return (weekdaysBySite[siteID]?.contains(weekday) ?? false)
                    && !(recorded[siteID]?.contains(date) ?? false)
            }
            if !missing.isEmpty { result.append(Evening(date: date, siteIDs: missing)) }
        }
        return result
    }

    /// The dates of `missing`, for a caller that only asks which evenings.
    static func dates(
        siteDays: [SiteDay],
        today: CalendarDate,
        calendar: Calendar,
        lookBackDays: Int = 14,
        daysAhead: Int = 7,
        holidays: Set<Int> = [],
        askedWhenLeavingToday: Set<UUID> = [],
        workDays: [UUID: Set<Int>] = [:],
        silenced: Set<UUID> = [],
        pauses: [UUID: SitePause] = [:],
        crewElsewhere: [UUID: Set<CalendarDate>] = [:]
    ) -> [CalendarDate] {
        missing(
            siteDays: siteDays, today: today, calendar: calendar, lookBackDays: lookBackDays, daysAhead: daysAhead,
            holidays: holidays, askedWhenLeavingToday: askedWhenLeavingToday, workDays: workDays,
            silenced: silenced, pauses: pauses, crewElsewhere: crewElsewhere
        ).map(\.date)
    }

    /// Whether a site's day is written: any site day stored for that site and
    /// date, whatever it holds. The evening reminder's rule, which the
    /// question on leaving a site shares.
    static func isWritten(siteID: UUID, on date: CalendarDate, siteDays: [SiteDay]) -> Bool {
        siteDays.contains { $0.siteID == siteID && $0.date == date }
    }
}

extension SiteReminderPlan {
    /// The evenings to nudge on, from what is stored: `missing` with each
    /// site's own say worked out here, so the app's refresher and the tests
    /// ask the same question.
    ///
    /// - `sites`: every site, archived ones too, in the Sites tab's order.
    ///   An archived site is never missing, whatever was written on it
    ///   lately: it is done.
    /// - `setup`: a site's work days, evening-reminder switch and pause.
    /// - `members`: every site's crew, hidden people too
    ///   (`SiteMonthOverview.crew`).
    /// - `siteDays`: every site's days from `lookBackDays` before `today`
    ///   up to today, today's included: what was just saved counts.
    /// - `lastDays`: for a site with nothing in that window, its last day
    ///   written, however old. It only says who that site's crew is: a
    ///   site with work days set that nobody has been to for three weeks
    ///   is still not expected on a day its whole crew is on another site.
    ///
    /// Today is not missing on a site whose whole crew is on another of
    /// your sites today (`SiteMonthOverview.isCrewElsewhere`): writing site
    /// A with everyone on it answers for site B.
    static func evenings(
        sites: [Site],
        setup: (UUID) -> SiteSetup,
        members: [CrewMember],
        siteDays: [SiteDay],
        lastDays: [SiteDay] = [],
        today: CalendarDate,
        calendar: Calendar,
        lookBackDays: Int = 14,
        daysAhead: Int = 7,
        holidays: Set<Int> = [],
        askedWhenLeavingToday: Set<UUID> = []
    ) -> [Evening] {
        var workDays: [UUID: Set<Int>] = [:]
        var silenced = Set<UUID>()
        var pauses: [UUID: SitePause] = [:]
        var crewElsewhere: [UUID: Set<CalendarDate>] = [:]
        // Who each site's crew is: the days in the window, and the last day
        // of a site that has none there.
        let inWindow = Set(siteDays.map(\.siteID))
        let history = siteDays + lastDays.filter { !inWindow.contains($0.siteID) && $0.date < today }
        for site in sites {
            guard !site.isArchived else {
                silenced.insert(site.id)
                continue
            }
            let setup = setup(site.id)
            if !setup.workDays.isEmpty { workDays[site.id] = setup.workDays }
            if !setup.eveningReminder { silenced.insert(site.id) }
            if let pause = setup.pause { pauses[site.id] = pause }
            if SiteMonthOverview.isCrewElsewhere(
                siteID: site.id, on: today, members: members, siteDays: history, calendar: calendar
            ) {
                crewElsewhere[site.id] = [today]
            }
        }
        return missing(
            siteDays: siteDays,
            today: today,
            calendar: calendar,
            lookBackDays: lookBackDays,
            daysAhead: daysAhead,
            holidays: holidays,
            askedWhenLeavingToday: askedWhenLeavingToday,
            workDays: workDays,
            silenced: silenced,
            pauses: pauses,
            crewElsewhere: crewElsewhere,
            order: sites.map(\.id)
        )
    }
}

/// What one evening's site reminder says and opens.
///
/// One site is named, and a tap opens it on today; two are both named; more
/// are counted. Two or more open the Sites tab, where each says how it
/// stands. The words are the app's (`ReminderScheduler`); what they are
/// about is decided here.
enum SiteReminderNotice: Hashable, Sendable {
    /// "<Site>: today's hours aren't written yet."
    case one(siteID: UUID, name: String)
    /// Both names.
    case two(first: String, second: String)
    /// "3 sites aren't written today."
    case several(count: Int)
    /// No site of the evening has a name to give: the plain sentence.
    case unnamed

    /// - `names`: the sites that can be named, by id; a site with none (it
    ///   is gone since the plan was made) is left out.
    init(_ evening: SiteReminderPlan.Evening, names: [UUID: String]) {
        let named = evening.siteIDs.compactMap { id -> (id: UUID, name: String)? in
            guard let name = names[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return (id, name)
        }
        switch named.count {
        case 0: self = .unnamed
        case 1: self = .one(siteID: named[0].id, name: named[0].name)
        case 2: self = .two(first: named[0].name, second: named[1].name)
        default: self = .several(count: named.count)
        }
    }

    /// Where a tap goes: the one site, on today, or the Sites tab.
    var link: AppLink {
        if case let .one(siteID, _) = self { return .site(siteID) }
        return .sites
    }
}
