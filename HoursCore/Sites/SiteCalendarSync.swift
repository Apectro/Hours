import Foundation

/// Carries the user's own hours on job sites into their personal calendar.
///
/// The site day is the single source of truth. A site shift in a `DayRecord`
/// is therefore never edited in place: it is thrown away and rebuilt from the
/// site days on every change, so ticking or unticking "you", or changing the
/// hours, can never leave a stale copy behind. Everything else on the day,
/// the manual shifts, the note, the day type, passes through untouched.
enum SiteCalendarSync {
    /// The personal record for `date` with its site shifts replaced by one
    /// shift per site day that has you present. Returns `nil` when nothing is
    /// left worth storing.
    ///
    /// Each shift's id is its site's id, and so is its break's, so merging the
    /// result again yields an equal record and storage and sync see no change.
    ///
    /// A bad-weather stop with no hours for you gives your day the Bad
    /// weather type, but only when nothing else is written on it: no type you
    /// chose, and no hours of your own or from another site. `previousSiteDays`
    /// is what was stored on that date before this change. When a stop that
    /// would have typed your day is no longer there — lifted, unticked or
    /// deleted — the type goes again. That is the one way to tell the type
    /// this put on from one you chose, which stays. A reason you were away
    /// (`SiteDay.absences`) types your day the same way.
    static func merged(
        personal: DayRecord?,
        siteDays: [SiteDay],
        on date: CalendarDate,
        previousSiteDays: [SiteDay] = []
    ) -> DayRecord? {
        var record = personal ?? DayRecord(date: date)
        record.shifts.removeAll { $0.siteID != nil }

        var seen = Set<UUID>()
        for day in siteDays where day.date == date {
            // Sync can deliver the same site day twice; the first one wins.
            guard seen.insert(day.siteID).inserted else { continue }
            guard let mine = day.resolved(for: CrewMember.youID) else { continue }
            record.shifts.append(
                Shift(
                    id: day.siteID,
                    start: mine.start,
                    end: mine.end,
                    breaks: mine.breakMinutes > 0
                        ? [BreakSpan(id: day.siteID, explicitMinutes: mine.breakMinutes)]
                        : [],
                    jobID: day.jobID,
                    siteID: day.siteID,
                    // The allowance and the van's kilometres ride on the
                    // site shift, rebuilt with it, so they follow the site
                    // day and never touch what you wrote on the day yourself.
                    fieldAllowance: day.hasAllowance(for: CrewMember.youID),
                    kilometres: day.kilometres
                )
            )
        }

        let onDate = siteDays.filter { $0.date == date }
        let stopped = onDate.contains { $0.isFullStop(for: CrewMember.youID) }
        let wasStopped = previousSiteDays.contains { $0.date == date && $0.isFullStop(for: CrewMember.youID) }
        if record.dayTypeID == .badWeather, wasStopped, !stopped {
            record.dayTypeID = nil
        }
        if record.dayTypeID == nil, stopped, record.shifts.allSatisfy(\.isEmpty) {
            record.dayTypeID = .badWeather
        }

        // You marked away on a site with a reason — Sick, Vacation — gives
        // your day that type by the same rule: only over nothing, and taken
        // back only when the reason this put on is gone or changed.
        let reason = onDate.lazy.compactMap { $0.absence(for: CrewMember.youID) }.first
        let previousReasons = Set(previousSiteDays.filter { $0.date == date }.compactMap { $0.absence(for: CrewMember.youID) })
        if let type = record.dayTypeID, previousReasons.contains(type), reason != type {
            record.dayTypeID = nil
        }
        if record.dayTypeID == nil, let reason, record.shifts.allSatisfy(\.isEmpty) {
            record.dayTypeID = reason
        }

        return record.isBlank ? nil : record
    }

    /// `merged` for every date that either input mentions, in date order. A
    /// site shift whose site has no day on that date is dropped, which is how
    /// a deleted site day or site leaves the calendar.
    static func rebuilt(days: [DayRecord], siteDays: [SiteDay]) -> [DayRecord] {
        let dates = Set(days.map(\.date)).union(siteDays.map(\.date)).sorted()
        // First record wins for a date, matching how a duplicate is read elsewhere.
        var byDate: [CalendarDate: DayRecord] = [:]
        for day in days where byDate[day.date] == nil { byDate[day.date] = day }
        return dates.compactMap { merged(personal: byDate[$0], siteDays: siteDays, on: $0) }
    }
}
