import Foundation

/// Which months are closed to editing.
///
/// Once a timesheet has been handed to payroll, the days behind it changing
/// silently is how a disagreement starts — and the app is otherwise built to
/// let you edit any day at any time, which is right up to the moment a month
/// has been sent somewhere.
///
/// A value rather than a flag on each day: the lock is a statement about a
/// period, and storing it per day would let a month be half locked, which is
/// not a state anybody means.
struct MonthLock: Codable, Hashable, Sendable {
    /// Months the user has closed by hand.
    var months: Set<YearMonth>

    init(months: Set<YearMonth> = []) {
        self.months = months
    }

    /// Nothing locked. The value every read-only path can use without
    /// pretending to know about editing.
    static let unlocked = MonthLock()

    func isLocked(_ month: YearMonth) -> Bool { months.contains(month) }

    func isLocked(_ date: CalendarDate) -> Bool { isLocked(YearMonth(date)) }

    /// Every month a range touches that is locked, in order — so a bulk edit
    /// can say which months stopped it rather than only that something did.
    func lockedMonths(in range: CalendarDateRange, calendar: Calendar) -> [YearMonth] {
        var seen: [YearMonth] = []
        var month = YearMonth(range.start)
        let last = YearMonth(range.end)
        while month <= last {
            if isLocked(month) { seen.append(month) }
            month = month.adding(months: 1)
        }
        return seen
    }

    mutating func lock(_ month: YearMonth) { months.insert(month) }

    mutating func unlock(_ month: YearMonth) { months.remove(month) }
}

extension MonthLock {
    /// Why a write was refused, for a caller that wants to say so.
    ///
    /// An error rather than a silent no-op. A save that quietly does nothing
    /// is the worst possible outcome here: the person believes their hours are
    /// recorded, and the app agrees with them until payday.
    enum Refusal: Error, Equatable {
        case monthIsClosed(YearMonth)
    }

    /// Throws when `date` falls in a closed month.
    func check(_ date: CalendarDate) throws {
        let month = YearMonth(date)
        guard isLocked(month) else { return }
        throw Refusal.monthIsClosed(month)
    }
}
