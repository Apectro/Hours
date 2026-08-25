import Foundation

/// A shift that has been started and not yet finished.
///
/// Held apart from the day's record rather than as a shift with no end time,
/// because those two states look identical in storage and mean opposite
/// things: one is a clock that is running, the other is a day someone forgot
/// to finish filling in.
///
/// `startedAt` is an absolute instant as well as a wall-clock time. The
/// wall-clock time is what gets recorded; the instant is what lets a display
/// tick, and what makes "how long have I been here" answerable across a
/// restart.
struct RunningShift: Codable, Hashable, Sendable {
    var date: CalendarDate
    var start: TimeOfDay
    var startedAt: Date
    var jobID: UUID?

    init(date: CalendarDate, start: TimeOfDay, startedAt: Date, jobID: UUID? = nil) {
        self.date = date
        self.start = start
        self.startedAt = startedAt
        self.jobID = jobID
    }

    /// Starts a shift from an instant, in the given calendar.
    init(startingAt instant: Date, calendar: Calendar, jobID: UUID? = nil) {
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        self.init(
            date: CalendarDate(instant, calendar: calendar),
            start: TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0),
            startedAt: instant,
            jobID: jobID
        )
    }

    /// Real seconds since the clock was started, never negative.
    func elapsedSeconds(at instant: Date) -> Int {
        max(0, Int(instant.timeIntervalSince(startedAt)))
    }

    func elapsedMinutes(at instant: Date) -> Int {
        elapsedSeconds(at: instant) / 60
    }

    /// A shift left running for longer than this is treated as forgotten
    /// rather than as a genuine multi-day stint.
    static let maximumSensibleHours = 24

    func hasRunTooLong(at instant: Date) -> Bool {
        elapsedSeconds(at: instant) >= RunningShift.maximumSensibleHours * 3600
    }

    /// The shift this becomes when stopped.
    ///
    /// The end is the wall-clock time of stopping, so an overnight shift ends
    /// "at 02:00" and the calculator reads that as the next day, exactly as if
    /// it had been typed in. A clock left running beyond a day is capped, since
    /// wall-clock times cannot express "and then another whole day".
    func finished(at instant: Date, calendar: Calendar) -> Shift {
        let capped = hasRunTooLong(at: instant)
        let end: TimeOfDay
        if capped {
            // One minute short of a full day: the longest thing two wall-clock
            // times can honestly describe.
            end = TimeOfDay(minutes: (start.minutes + TimeOfDay.minutesPerDay - 1) % TimeOfDay.minutesPerDay)
        } else {
            let parts = calendar.dateComponents([.hour, .minute], from: instant)
            end = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
        return Shift(start: start, end: end, jobID: jobID)
    }
}
