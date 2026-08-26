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

    init(
        id: UUID = UUID(),
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breaks: [BreakSpan] = [],
        jobID: UUID? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.breaks = breaks
        self.jobID = jobID
    }

    var hasTimes: Bool { start != nil && end != nil }

    /// True when the shift carries nothing worth keeping.
    var isEmpty: Bool {
        start == nil && end == nil && breaks.allSatisfy(\.isEmpty)
    }

    /// Every break in this shift, timed or plain, as entered.
    ///
    /// Was `totalExplicitBreakMinutes` and summed only `explicitMinutes`, so a
    /// break recorded as 12:00–12:30 counted as nothing. Nothing called it,
    /// which is the only reason that never showed anywhere.
    var totalBreakMinutes: Int {
        breaks.reduce(0) { $0 + $1.minutes }
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, breaks, jobID
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
            jobID: container.lenientOptional(.jobID, UUID.self)
        )
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
}
