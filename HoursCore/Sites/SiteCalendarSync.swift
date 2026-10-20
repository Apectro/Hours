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
    static func merged(personal: DayRecord?, siteDays: [SiteDay], on date: CalendarDate) -> DayRecord? {
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
                    siteID: day.siteID
                )
            )
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
