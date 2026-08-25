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

    var start: TimeOfDay?
    var end: TimeOfDay?
    var breaks: [BreakSpan]

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
        self.start = start
        self.end = end
        self.breaks = breaks
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

    var hasTimes: Bool { start != nil && end != nil }

    var totalExplicitBreakMinutes: Int {
        breaks.reduce(0) { $0 + ($1.explicitMinutes ?? 0) }
    }

    /// True when the record carries no information worth persisting. The editor
    /// uses this to delete rather than store empty rows, which keeps "has data"
    /// indicators on the calendar honest.
    var isBlank: Bool {
        dayTypeID == nil
            && start == nil
            && end == nil
            && breaks.allSatisfy { $0.isEmpty }
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
