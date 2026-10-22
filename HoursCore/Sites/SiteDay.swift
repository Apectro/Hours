import Foundation

/// One person's presence on a site day. Any `nil` field means "use the
/// site's", so the common case, everyone working the same hours, stores
/// nothing per person.
struct Attendance: Hashable, Codable, Sendable {
    var memberID: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int?

    init(memberID: UUID, start: TimeOfDay? = nil, end: TimeOfDay? = nil, breakMinutes: Int? = nil) {
        self.memberID = memberID
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case memberID, start, end, breakMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            memberID: container.lenient(.memberID, UUID()),
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenientOptional(.breakMinutes)
        )
    }
}

/// The hours a crew worked on one site on one date.
struct SiteDay: Hashable, Codable, Sendable {
    var siteID: UUID
    var date: CalendarDate
    var start: TimeOfDay?
    var end: TimeOfDay?
    /// The site's break; attendances may override it.
    var breakMinutes: Int
    var present: [Attendance]
    var note: String
    /// The job these hours count towards, frozen when the day is written so
    /// that later changes to the site never move recorded hours between jobs.
    var jobID: UUID?
    /// The crew was rained off: a bad-weather stop (Schlechtwetter). Either
    /// no hours at all, or the hours up to the stop; see
    /// `stoppedForBadWeather(at:)`.
    var isBadWeatherStop: Bool

    init(
        siteID: UUID,
        date: CalendarDate,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breakMinutes: Int = 0,
        present: [Attendance] = [],
        note: String = "",
        jobID: UUID? = nil,
        isBadWeatherStop: Bool = false
    ) {
        self.siteID = siteID
        self.date = date
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.present = present
        self.note = note
        self.jobID = jobID
        self.isBadWeatherStop = isBadWeatherStop
    }

    func attendance(for memberID: UUID) -> Attendance? {
        present.first { $0.memberID == memberID }
    }

    /// One person's hours on this day: their own override where they have one,
    /// the site's value otherwise. `nil` when they are not present. The single
    /// place this is decided, so the site screen and the calendar cannot
    /// disagree about it.
    func resolved(for memberID: UUID) -> (start: TimeOfDay?, end: TimeOfDay?, breakMinutes: Int)? {
        guard let attendance = attendance(for: memberID) else { return nil }
        return (
            attendance.start ?? start,
            attendance.end ?? end,
            attendance.breakMinutes ?? breakMinutes
        )
    }

    /// True when there is nothing worth storing: nobody ticked, no site times
    /// and no note. The day screen deletes such a day rather than keeping an
    /// empty row, as the calendar does with a blank `DayRecord`. A break on
    /// its own does not count, because it means nothing without times; a
    /// note does, because "rain, nobody came" is worth keeping and dropping
    /// typed text would be a save that silently did nothing.
    var isBlank: Bool {
        !isBadWeatherStop
            && present.isEmpty
            && start == nil
            && end == nil
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the member was present but worked different hours from the
    /// site's, which is what the day editor flags.
    func hasException(_ memberID: UUID) -> Bool {
        guard let attendance = attendance(for: memberID) else { return false }
        return attendance.start != nil || attendance.end != nil || attendance.breakMinutes != nil
    }

    // MARK: - Bad weather

    /// The day as a bad-weather stop for the whole crew.
    ///
    /// With no time, nobody worked: the site's times, its break and
    /// everyone's own times go, and who was there stays, because "the crew turned up and was
    /// sent home" is the fact the director needs. With a time — "stopped at
    /// 11:00" — the hours until then stand: the site's end becomes the stop,
    /// and anyone whose own end was later stops with everyone else, while
    /// someone who had already left keeps the time they left.
    ///
    /// A stop before the day's start, or on a day running past midnight, is
    /// taken at its word only for the site's end; nobody's start is moved.
    func stoppedForBadWeather(at stop: TimeOfDay?) -> SiteDay {
        var day = self
        day.isBadWeatherStop = true
        guard let stop else {
            day.start = nil
            day.end = nil
            day.breakMinutes = 0
            day.present = present.map { Attendance(memberID: $0.memberID) }
            return day
        }
        day.end = stop
        day.present = present.map { attendance in
            var stopped = attendance
            if let own = attendance.end, own.minutes > stop.minutes {
                stopped.end = stop
            }
            return stopped
        }
        return day
    }

    /// The stop taken back. The times stay as they are, to be corrected by hand.
    func liftingBadWeatherStop() -> SiteDay {
        var day = self
        day.isBadWeatherStop = false
        return day
    }

    /// Whether this day was a full stop for `memberID`: rained off, present,
    /// and no hours to show for it.
    func isFullStop(for memberID: UUID) -> Bool {
        guard isBadWeatherStop, let mine = resolved(for: memberID) else { return false }
        return mine.start == nil || mine.end == nil
    }

    private enum CodingKeys: String, CodingKey {
        case siteID, date, start, end, breakMinutes, present, note, jobID, isBadWeatherStop
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            siteID: container.lenient(.siteID, UUID()),
            date: container.lenient(.date, CalendarDate(year: 1970, month: 1, day: 1)),
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenient(.breakMinutes, 0),
            present: container.lenient(.present, []),
            note: container.lenient(.note, ""),
            jobID: container.lenientOptional(.jobID),
            isBadWeatherStop: container.lenient(.isBadWeatherStop, false)
        )
    }
}
