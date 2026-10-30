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

    /// Breaks already taken on this clock (1.2, Today's Break button), as
    /// the times they were taken: they go onto the shift when it stops.
    var breaks: [BreakSpan] = []
    /// The break running now, if any: when it began, as an instant (for the
    /// ticking figure) and as a wall-clock time (for the record).
    var breakStartedAt: Date?
    var breakStart: TimeOfDay?
    /// Real seconds of the breaks already taken, so the worked figure does
    /// not depend on wall-clock arithmetic across midnight.
    var breakSeconds: Int = 0

    init(date: CalendarDate, start: TimeOfDay, startedAt: Date, jobID: UUID? = nil) {
        self.date = date
        self.start = start
        self.startedAt = startedAt
        self.jobID = jobID
    }

    private enum CodingKeys: String, CodingKey {
        case date, start, startedAt, jobID, breaks, breakStartedAt, breakStart, breakSeconds
    }

    /// Lenient about the break fields: a clock started before they existed
    /// is still running after the update, and must load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(CalendarDate.self, forKey: .date),
            start: try container.decode(TimeOfDay.self, forKey: .start),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            jobID: try container.decodeIfPresent(UUID.self, forKey: .jobID)
        )
        breaks = (try? container.decodeIfPresent([BreakSpan].self, forKey: .breaks)) ?? []
        breakStartedAt = try? container.decodeIfPresent(Date.self, forKey: .breakStartedAt)
        breakStart = try? container.decodeIfPresent(TimeOfDay.self, forKey: .breakStart)
        breakSeconds = max(0, (try? container.decodeIfPresent(Int.self, forKey: .breakSeconds)) ?? 0)
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

    // MARK: - Breaks

    /// A break is running now.
    var isOnBreak: Bool { breakStartedAt != nil }

    /// Seconds worked: the time since the clock started, less every break,
    /// the one running now included. Stands still during a break.
    func workedSeconds(at instant: Date) -> Int {
        let current = breakStartedAt.map { max(0, Int(instant.timeIntervalSince($0))) } ?? 0
        return max(0, elapsedSeconds(at: instant) - breakSeconds - current)
    }

    /// The clock with a break begun at `instant`. A break already running
    /// is kept as it is, so a second tap cannot move its start.
    func startingBreak(at instant: Date, calendar: Calendar) -> RunningShift {
        guard !isOnBreak else { return self }
        var copy = self
        copy.breakStartedAt = max(instant, startedAt)
        copy.breakStart = Self.wallClock(max(instant, startedAt), calendar: calendar)
        return copy
    }

    /// The clock with the running break ended at `instant` and kept.
    func endingBreak(at instant: Date, calendar: Calendar) -> RunningShift {
        guard let began = breakStartedAt, let from = breakStart else { return self }
        var copy = self
        let end = max(instant, began)
        copy.breaks.append(.timed(from: from, to: Self.wallClock(end, calendar: calendar)))
        copy.breakSeconds += max(0, Int(end.timeIntervalSince(began)))
        copy.breakStartedAt = nil
        copy.breakStart = nil
        return copy
    }

    private static func wallClock(_ instant: Date, calendar: Calendar) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
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
        // A break still running when the clock stops ends where it does.
        let taken = isOnBreak ? endingBreak(at: instant, calendar: calendar).breaks : breaks
        return Shift(start: start, end: end, breaks: taken, jobID: jobID)
    }
}
