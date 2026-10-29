import Foundation

/// Your clock following you to another site (1.2).
///
/// When you are among those who "Moved to another site…" while your clock
/// runs, the clock stops at the time you left and starts again at the time
/// you started there, through the same `TimeClock` as the widgets and Siri.
/// The morning is then a finished shift and the clock that runs is the
/// other site's, so the Live Activity and the widget follow the move.
struct ClockHandover: Hashable, Sendable {
    /// When the running clock stops: the time you left.
    let stopAt: Date
    /// When it starts again: the time you started on the other site, never
    /// before `stopAt`.
    let restartAt: Date
}

enum ClockFollowsMove {
    /// What happens to the clock, or nil when nothing should: no clock, you
    /// stayed, the move is on another day than the one the clock runs on, or
    /// the clock started at or after the time you left (it is already the
    /// other site's).
    static func handover(
        running: RunningShift?,
        youMoved: Bool,
        date: CalendarDate,
        left: TimeOfDay,
        started: TimeOfDay,
        calendar: Calendar
    ) -> ClockHandover? {
        guard let running, youMoved, running.date == date, running.start < left else { return nil }
        guard let stop = left.date(on: date, in: calendar),
              let start = started.date(on: date, in: calendar)
        else { return nil }
        let stopAt = max(stop, running.startedAt)
        return ClockHandover(stopAt: stopAt, restartAt: max(start, stopAt))
    }
}
