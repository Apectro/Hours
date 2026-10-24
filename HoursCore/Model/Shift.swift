import Foundation

/// One continuous block of work within a day.
///
/// A day holds a list of these rather than a single start and end, because a
/// split shift — mornings and evenings with the middle of the day off — is a
/// real working pattern and faking it with a four-hour "break" misreports both
/// the hours and the day's shape.
struct Shift: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breaks: [BreakSpan]

    /// Which job this block of work belongs to. `nil` means the default job,
    /// which is what every shift is until a second job exists.
    var jobID: UUID?

    /// Set when this shift was derived from the user's own hours on a job
    /// site. The site day is the single source of truth: such a shift is
    /// rebuilt from it whenever the site day changes, never edited here.
    var siteID: UUID?

    /// On a site shift only: the site day gave you the field allowance
    /// (`SiteDay.hasAllowance(for:)`). Rebuilt with the shift, so it follows
    /// the site day and never touches the allowance you set on the day
    /// yourself (`DayRecord.hasFieldAllowance`).
    var fieldAllowance: Bool

    /// On a site shift only: the site day's vehicle kilometres, as above.
    var kilometres: Int

    init(
        id: UUID = UUID(),
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breaks: [BreakSpan] = [],
        jobID: UUID? = nil,
        siteID: UUID? = nil,
        fieldAllowance: Bool = false,
        kilometres: Int = 0
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.breaks = breaks
        self.jobID = jobID
        self.siteID = siteID
        self.fieldAllowance = fieldAllowance
        self.kilometres = max(0, kilometres)
    }

    var hasTimes: Bool { start != nil && end != nil }

    /// True when the shift carries nothing worth keeping.
    ///
    /// About the hours only: a site shift that carries an allowance or
    /// kilometres and no times is still empty here, so a full bad-weather
    /// stop still types the day. Whether it is worth storing is
    /// `hasSiteExtras` as well.
    var isEmpty: Bool {
        start == nil && end == nil && breaks.allSatisfy(\.isEmpty)
    }

    /// A site shift carrying the field allowance or kilometres.
    var hasSiteExtras: Bool { fieldAllowance || kilometres > 0 }

    /// Every break in this shift, timed or plain, as entered.
    ///
    /// Was `totalExplicitBreakMinutes` and summed only `explicitMinutes`, so a
    /// break recorded as 12:00–12:30 counted as nothing. Nothing called it,
    /// which is the only reason that never showed anywhere.
    var totalBreakMinutes: Int {
        breaks.reduce(0) { $0 + $1.minutes }
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, breaks, jobID, siteID, fieldAllowance, kilometres
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Strict about the times and the breaks; lenient about the rest.
        //
        // Those three fields are the hours. Read leniently, a damaged start
        // time becomes "no start time" — a day that looks deliberately blank,
        // which is indistinguishable on screen from a day someone genuinely did
        // not work. Throwing is what lets the archive count that day as damaged
        // and name it, so it can be typed back in.
        //
        // The id and the job stay lenient: a fresh id is harmless, and a shift
        // pointing at a job that no longer exists already falls back to the
        // primary one by design.
        self.init(
            id: container.lenient(.id, UUID()),
            start: try container.decodeIfPresent(TimeOfDay.self, forKey: .start),
            end: try container.decodeIfPresent(TimeOfDay.self, forKey: .end),
            breaks: try container.decodeIfPresent([BreakSpan].self, forKey: .breaks) ?? [],
            jobID: container.lenientOptional(.jobID, UUID.self),
            siteID: container.lenientOptional(.siteID, UUID.self),
            fieldAllowance: container.lenient(.fieldAllowance, false),
            kilometres: container.lenient(.kilometres, 0)
        )
    }

    /// Written by hand so the two site extras go in only when set: every
    /// other shift is written exactly as before.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encode(breaks, forKey: .breaks)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encodeIfPresent(siteID, forKey: .siteID)
        if fieldAllowance { try container.encode(fieldAllowance, forKey: .fieldAllowance) }
        if kilometres != 0 { try container.encode(kilometres, forKey: .kilometres) }
    }
}

/// A shift as the engine resolved it, with its arithmetic done.
struct ShiftPeriod: Identifiable, Hashable, Sendable {
    var id: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    var workedMinutes: Int
    var breakMinutes: Int
    var crossesMidnight: Bool
    var jobID: UUID?
    /// The timed breaks, as minutes after the start, clipped to the shift and
    /// merged. What earnings need to know which minutes of a night were worked;
    /// a break with no times has no place, and is only in `breakMinutes`.
    var timedBreaks: [Range<Int>] = []
    /// The site a shift written from a site day belongs to; nil for one
    /// typed into the calendar.
    var siteID: UUID? = nil
}
