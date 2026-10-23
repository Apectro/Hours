import Foundation

/// Export's ‹ › arrows for your own timesheet.
///
/// Export used to open on whatever the calendar showed and offer no way to
/// move: sending last month meant closing it, paging the calendar back and
/// opening it again. The arrows step the range by its own length — a day, a
/// week, a month, a year — and stop at the period holding today, since there
/// is nothing to hand over from a period that has not started.
extension ExportRangeKind {
    /// A custom range has no length to step by; its two dates are the control.
    var steps: Bool { self != .custom }

    /// `anchor` moved `direction` whole periods. A month or year step keeps
    /// the day inside the month it lands in: the 31st of October goes back to
    /// the 30th of September rather than spilling into October again.
    func step(_ anchor: CalendarDate, by direction: Int, calendar: Calendar) -> CalendarDate {
        switch self {
        case .day:
            return anchor.adding(days: direction, in: calendar)
        case .week:
            return anchor.adding(days: 7 * direction, in: calendar)
        case .month:
            return Self.clamped(anchor.day, in: YearMonth(anchor).adding(months: direction), calendar: calendar)
        case .year:
            return Self.clamped(anchor.day, in: YearMonth(year: anchor.year + direction, month: anchor.month), calendar: calendar)
        case .custom:
            return anchor
        }
    }

    /// Whether the next period has started by `today`.
    func canStepForward(from anchor: CalendarDate, today: CalendarDate, calendar: Calendar) -> Bool {
        switch self {
        case .day:
            return anchor < today
        case .week:
            let next = CalendarDateRange.week(containing: anchor, in: calendar).start.adding(days: 7, in: calendar)
            return next <= today
        case .month:
            return YearMonth(anchor) < YearMonth(today)
        case .year:
            return anchor.year < today.year
        case .custom:
            return false
        }
    }

    private static func clamped(_ day: Int, in month: YearMonth, calendar: Calendar) -> CalendarDate {
        CalendarDate(year: month.year, month: month.month, day: min(day, month.dayCount(in: calendar)))
    }
}

/// What the calendar's month menu offers for the month on screen.
enum MonthLockOffer: Equatable, Sendable {
    /// A finished month that is still open.
    case close
    /// A closed month, whichever it is: undoing must always be possible.
    case reopen
}

extension MonthLock {
    /// Closing only a finished month, as Settings always has: closing the
    /// month you are still in would refuse today's hours.
    func offer(for month: YearMonth, today: CalendarDate) -> MonthLockOffer? {
        if isLocked(month) { return .reopen }
        return month < YearMonth(today) ? .close : nil
    }
}
