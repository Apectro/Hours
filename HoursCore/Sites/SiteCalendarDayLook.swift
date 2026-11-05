import Foundation

/// How a day of a site's month grid is drawn (`SiteMonthCalendar`), from its
/// status (`SiteDayStatus`) and what the personal calendar shows on the same
/// day (`CalendarDayLook`): a public holiday reads as one on both, on a tile
/// in the holiday type's colour with its word under the date; a holiday the
/// crew worked shows the written tile and keeps a small holiday mark. A day
/// a paused site would have been worked reads as paused.
struct SiteCalendarDayLook: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Written, everyone accounted for.
        case written
        /// Written, someone on the crew neither ticked nor given a reason.
        case partly
        /// A work day gone by that nobody wrote.
        case missing
        /// A work day from today on, nothing written yet.
        case future
        /// A public holiday off, nothing written.
        case holiday
        /// Recorded as "no work".
        case noWork
        /// The whole crew was on another of your sites.
        case elsewhere
        /// A work day of the site while it is paused, nothing written.
        case paused
        /// Not a work day of the site, nothing written.
        case dayOff
    }

    var kind: Kind
    /// The public holiday off on the day, whatever is written on it.
    var holidayName: String?

    init(kind: Kind, holidayName: String? = nil) {
        self.kind = kind
        self.holidayName = holidayName
    }

    /// Whether the day sits on a tile (today aside, which always does):
    /// written, partly written, missing, and a holiday, as on the personal
    /// calendar.
    var hasTile: Bool {
        switch kind {
        case .written, .partly, .missing, .holiday: return true
        case .future, .noWork, .elsewhere, .paused, .dayOff: return false
        }
    }

    /// A holiday with something else drawn on it (written, partly, no
    /// work): the small holiday mark beside what is under the date.
    var hasHolidayMark: Bool {
        holidayName != nil && kind != .holiday
    }

    /// Drawn like a day off: the date in the secondary colour, no tile.
    var isNeutral: Bool {
        switch kind {
        case .dayOff, .noWork, .elsewhere, .paused: return true
        case .written, .partly, .missing, .future, .holiday: return false
        }
    }

    /// One day's look.
    ///
    /// - `holidayName`: the public holiday off on the day, if any.
    /// - `wouldBeExpected`: whether a work day would be expected on it with
    ///   the pause lifted; asked only of a day off while paused.
    static func of(
        _ status: SiteDayStatus,
        holidayName: String?,
        isPaused: Bool,
        wouldBeExpected: () -> Bool
    ) -> SiteCalendarDayLook {
        switch status {
        case .written: return SiteCalendarDayLook(kind: .written, holidayName: holidayName)
        case .partly: return SiteCalendarDayLook(kind: .partly, holidayName: holidayName)
        case .missing: return SiteCalendarDayLook(kind: .missing, holidayName: holidayName)
        case .future: return SiteCalendarDayLook(kind: .future, holidayName: holidayName)
        case .noWork: return SiteCalendarDayLook(kind: .noWork, holidayName: holidayName)
        case .elsewhere: return SiteCalendarDayLook(kind: .elsewhere, holidayName: holidayName)
        case .dayOff:
            if let holidayName { return SiteCalendarDayLook(kind: .holiday, holidayName: holidayName) }
            if isPaused, wouldBeExpected() { return SiteCalendarDayLook(kind: .paused) }
            return SiteCalendarDayLook(kind: .dayOff)
        }
    }
}
