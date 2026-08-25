import Foundation

/// Everything the user entered about one day, as a value type.
///
/// This is the calculation engine's input. It is deliberately free of any
/// persistence or UI concerns: `DayEntry` (SwiftData) maps to and from it, and
/// tests construct it directly.
struct DayRecord: Identifiable, Hashable, Codable, Sendable {
    var date: CalendarDate

    /// `nil` means "derive it" — holiday rules, then the weekly schedule, then
    /// a plain working day. An explicit value always wins.
    var dayTypeID: DayTypeID?

    /// The blocks of work in this day. Usually exactly one.
    var shifts: [Shift]

    /// Set when automatic worked-hours calculation is off, or when the user
    /// overrides the computed value for this one day.
    var manualWorkedMinutes: Int?

    /// Replaces the contracted hours for this day only (half days, partial
    /// leave, a short Friday).
    var expectedOverrideMinutes: Int?

    /// Signed correction applied to the balance, e.g. an agreed rounding or a
    /// payout of overtime. Kept separate from worked time so reports can show
    /// the raw hours *and* the adjusted balance.
    var adjustmentMinutes: Int

    /// Set when automatic overtime calculation is off: the balance is then
    /// whatever the user says it is.
    var manualBalanceMinutes: Int?

    var note: String
    var location: String
    var tags: [String]

    /// Excluded days keep their data but contribute nothing to any total.
    var isIncluded: Bool

    /// The zone the shift was actually worked in. Only consulted by the
    /// `elapsedReal` duration policy; `nil` means "the device's current zone".
    var timeZoneIdentifier: String?

    init(
        date: CalendarDate,
        dayTypeID: DayTypeID? = nil,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breaks: [BreakSpan] = [],
        shifts: [Shift]? = nil,
        manualWorkedMinutes: Int? = nil,
        expectedOverrideMinutes: Int? = nil,
        adjustmentMinutes: Int = 0,
        manualBalanceMinutes: Int? = nil,
        note: String = "",
        location: String = "",
        tags: [String] = [],
        isIncluded: Bool = true,
        timeZoneIdentifier: String? = nil
    ) {
        self.date = date
        self.dayTypeID = dayTypeID
        // An explicit shift list wins; otherwise the single-shift arguments
        // build one, and a day with none of them starts with no shifts at all.
        if let shifts {
            self.shifts = shifts
        } else if start != nil || end != nil || !breaks.isEmpty {
            self.shifts = [Shift(start: start, end: end, breaks: breaks)]
        } else {
            self.shifts = []
        }
        self.manualWorkedMinutes = manualWorkedMinutes
        self.expectedOverrideMinutes = expectedOverrideMinutes
        self.adjustmentMinutes = adjustmentMinutes
        self.manualBalanceMinutes = manualBalanceMinutes
        self.note = note
        self.location = location
        self.tags = tags
        self.isIncluded = isIncluded
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var id: Int { date.key }

    // MARK: - Single-shift accessors
    //
    // The overwhelming majority of days are one shift, so these address the
    // first one and let the rest of the app stay simple. Multi-shift editing
    // goes through `shifts` directly.

    var start: TimeOfDay? {
        get { shifts.first?.start }
        set { updateFirstShift(discardIfEmpty: newValue == nil) { $0.start = newValue } }
    }

    var end: TimeOfDay? {
        get { shifts.first?.end }
        set { updateFirstShift(discardIfEmpty: newValue == nil) { $0.end = newValue } }
    }

    var breaks: [BreakSpan] {
        get { shifts.first?.breaks ?? [] }
        set { updateFirstShift(discardIfEmpty: newValue.isEmpty) { $0.breaks = newValue } }
    }

    /// Breaks across every shift, which is what totals need.
    var allBreaks: [BreakSpan] { shifts.flatMap(\.breaks) }

    private mutating func updateFirstShift(discardIfEmpty: Bool, _ change: (inout Shift) -> Void) {
        if shifts.isEmpty {
            // Setting a value to nothing on a day that has no shifts should not
            // conjure an empty one into existence.
            guard !discardIfEmpty else { return }
            shifts = [Shift()]
        }
        change(&shifts[0])
    }

    var hasTimes: Bool { shifts.contains(where: \.hasTimes) }

    var totalExplicitBreakMinutes: Int {
        allBreaks.reduce(0) { $0 + ($1.explicitMinutes ?? 0) }
    }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case date, dayTypeID, shifts
        case manualWorkedMinutes, expectedOverrideMinutes, adjustmentMinutes, manualBalanceMinutes
        case note, location, tags, isIncluded, timeZoneIdentifier
        // Written by versions that held a single shift on the day itself. Read
        // so that a backup taken before shifts existed still restores.
        case legacyStart = "start"
        case legacyEnd = "end"
        case legacyBreaks = "breaks"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let date = try container.decode(CalendarDate.self, forKey: .date)

        let shifts: [Shift]
        if let stored = container.lenientOptional(.shifts, [Shift].self), !stored.isEmpty {
            shifts = stored
        } else {
            let start = container.lenientOptional(.legacyStart, TimeOfDay.self)
            let end = container.lenientOptional(.legacyEnd, TimeOfDay.self)
            let breaks: [BreakSpan] = container.lenient(.legacyBreaks, [])
            shifts = (start == nil && end == nil && breaks.isEmpty)
                ? []
                : [Shift(start: start, end: end, breaks: breaks)]
        }

        self.init(
            date: date,
            dayTypeID: container.lenientOptional(.dayTypeID, DayTypeID.self),
            shifts: shifts,
            manualWorkedMinutes: container.lenientOptional(.manualWorkedMinutes, Int.self),
            expectedOverrideMinutes: container.lenientOptional(.expectedOverrideMinutes, Int.self),
            adjustmentMinutes: container.lenient(.adjustmentMinutes, 0),
            manualBalanceMinutes: container.lenientOptional(.manualBalanceMinutes, Int.self),
            note: container.lenient(.note, ""),
            location: container.lenient(.location, ""),
            tags: container.lenient(.tags, []),
            isIncluded: container.lenient(.isIncluded, true),
            timeZoneIdentifier: container.lenientOptional(.timeZoneIdentifier, String.self)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(dayTypeID, forKey: .dayTypeID)
        try container.encode(shifts, forKey: .shifts)
        try container.encodeIfPresent(manualWorkedMinutes, forKey: .manualWorkedMinutes)
        try container.encodeIfPresent(expectedOverrideMinutes, forKey: .expectedOverrideMinutes)
        try container.encode(adjustmentMinutes, forKey: .adjustmentMinutes)
        try container.encodeIfPresent(manualBalanceMinutes, forKey: .manualBalanceMinutes)
        try container.encode(note, forKey: .note)
        try container.encode(location, forKey: .location)
        try container.encode(tags, forKey: .tags)
        try container.encode(isIncluded, forKey: .isIncluded)
        try container.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }

    /// True when the record carries no information worth persisting. The editor
    /// uses this to delete rather than store empty rows, which keeps "has data"
    /// indicators on the calendar honest.
    var isBlank: Bool {
        dayTypeID == nil
            && shifts.allSatisfy(\.isEmpty)
            && manualWorkedMinutes == nil
            && expectedOverrideMinutes == nil
            && adjustmentMinutes == 0
            && manualBalanceMinutes == nil
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tags.isEmpty
            && isIncluded
    }
}
