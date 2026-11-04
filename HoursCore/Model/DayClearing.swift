import Foundation

/// What clearing a day writes: the editor's "Clear this day" and the
/// calendar week list's swipe (1.3) both go through this.
///
/// Everything typed in for the day goes. Hours written on a site stay: they
/// belong to the site's day and go when it does, on the site.
enum DayClearing: Equatable, Sendable {
    /// Nothing of yours is stored for the day.
    case nothing
    /// Delete the stored day outright.
    case delete(CalendarDate)
    /// Store this instead: the day's site hours alone.
    case keep(DayRecord)

    static func plan(for stored: DayRecord?) -> DayClearing {
        guard let stored else { return .nothing }
        let siteShifts = stored.shifts.filter { $0.siteID != nil }
        guard !siteShifts.isEmpty else { return .delete(stored.date) }
        let kept = DayRecord(date: stored.date, shifts: siteShifts)
        return kept == stored ? .nothing : .keep(kept)
    }
}
