import Foundation

/// One break within a shift.
///
/// A break is either *timed* (start and end on the clock) or a plain
/// *duration*. Both forms are supported because people record breaks both ways,
/// and mixing them within a day is allowed.
struct BreakSpan: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    /// Used when `start`/`end` are absent. Never negative.
    var explicitMinutes: Int?

    init(id: UUID = UUID(), start: TimeOfDay? = nil, end: TimeOfDay? = nil, explicitMinutes: Int? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.explicitMinutes = explicitMinutes.map { max(0, $0) }
    }

    /// A break expressed only as a length, e.g. "30 min".
    static func duration(_ minutes: Int) -> BreakSpan {
        BreakSpan(explicitMinutes: max(0, minutes))
    }

    /// A break pinned to the clock, e.g. 12:00–12:30.
    static func timed(from start: TimeOfDay, to end: TimeOfDay) -> BreakSpan {
        BreakSpan(start: start, end: end)
    }

    var isTimed: Bool { start != nil && end != nil }

    /// How long this break is, whichever of the two ways it was recorded.
    ///
    /// The nominal length, not the counted one: the calculator additionally
    /// clips breaks to the shift they sit in and merges overlapping ones, so a
    /// break running past the end of a shift counts for less than it says
    /// here. This is the number to *show* someone — what they entered — while
    /// the calculator's is the number their hours are worked out from.
    ///
    /// A timed break whose end is before its start ran past midnight.
    var minutes: Int {
        guard let start, let end else { return explicitMinutes ?? 0 }
        let span = end.minutes - start.minutes
        return span >= 0 ? span : span + TimeOfDay.minutesPerDay
    }

    var isEmpty: Bool {
        if isTimed { return false }
        return (explicitMinutes ?? 0) == 0
    }
}
