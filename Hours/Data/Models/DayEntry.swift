import Foundation
import SwiftData

/// One stored day.
///
/// Every property is a primitive. No enums, no `Date`s, no nested Codable
/// types are persisted directly, which keeps schema evolution additive and
/// keeps SwiftData out of the calculation engine — the engine only ever sees
/// the `DayRecord` value type this maps to.
@Model
final class DayEntry {
    /// `yyyyMMdd`. Unique, so a duplicate entry for a day is impossible at the
    /// storage layer rather than by convention.
    @Attribute(.unique) var dateKey: Int = 0

    /// `nil` means the day type is derived from holidays and the schedule.
    var dayTypeRawValue: String?

    /// JSON-encoded `[Shift]`. Encoded rather than modelled as a relation
    /// because shifts have no identity outside their day and should be written,
    /// read and deleted atomically with it.
    var shiftsData: Data?

    // Written by versions that stored a single shift on the day itself. Still
    // read, so an existing store keeps working; new writes leave them nil.
    var startMinutes: Int?
    var endMinutes: Int?
    var breaksData: Data?

    var manualWorkedMinutes: Int?
    var expectedOverrideMinutes: Int?
    var manualBalanceMinutes: Int?
    var adjustmentMinutes: Int = 0

    var note: String = ""
    var locationName: String = ""
    /// Newline-separated; tags are sanitised of newlines on the way in.
    var tagsJoined: String = ""

    var isIncluded: Bool = true
    var timeZoneIdentifier: String?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(dateKey: Int) {
        self.dateKey = dateKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension DayEntry {
    private static let tagSeparator = "\n"

    /// The value-type view of this entry, as handed to the calculation engine.
    var record: DayRecord {
        DayRecord(
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            dayTypeID: dayTypeRawValue.map { DayTypeID($0) },
            shifts: resolvedShifts,
            manualWorkedMinutes: manualWorkedMinutes,
            expectedOverrideMinutes: expectedOverrideMinutes,
            adjustmentMinutes: adjustmentMinutes,
            manualBalanceMinutes: manualBalanceMinutes,
            note: note,
            location: locationName,
            tags: tagsJoined.isEmpty ? [] : tagsJoined.components(separatedBy: DayEntry.tagSeparator),
            isIncluded: isIncluded,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    /// The shifts this entry holds, reading the legacy single-shift columns
    /// when the store predates the shift list.
    var resolvedShifts: [Shift] {
        if let shiftsData, !shiftsData.isEmpty,
           let decoded = try? JSONDecoder().decode([Shift].self, from: shiftsData) {
            return decoded
        }
        let start = startMinutes.map { TimeOfDay(minutes: $0) }
        let end = endMinutes.map { TimeOfDay(minutes: $0) }
        let breaks = DayEntry.decodeBreaks(breaksData)
        guard start != nil || end != nil || !breaks.isEmpty else { return [] }
        return [Shift(start: start, end: end, breaks: breaks)]
    }

    /// Copies a record onto this entry. `dateKey` is never changed — moving a
    /// day means deleting and re-creating it, so the unique index stays sound.
    func apply(_ record: DayRecord) {
        dayTypeRawValue = record.dayTypeID?.rawValue
        shiftsData = DayEntry.encodeShifts(record.shifts)
        // Clear the legacy columns so the migrated shape is the only source.
        startMinutes = nil
        endMinutes = nil
        breaksData = nil
        manualWorkedMinutes = record.manualWorkedMinutes
        expectedOverrideMinutes = record.expectedOverrideMinutes
        manualBalanceMinutes = record.manualBalanceMinutes
        adjustmentMinutes = record.adjustmentMinutes
        note = record.note
        locationName = record.location
        tagsJoined = record.tags
            .map { $0.replacingOccurrences(of: DayEntry.tagSeparator, with: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: DayEntry.tagSeparator)
        isIncluded = record.isIncluded
        timeZoneIdentifier = record.timeZoneIdentifier
        updatedAt = Date()
    }

    static func encodeShifts(_ shifts: [Shift]) -> Data? {
        let meaningful = shifts.filter { !$0.isEmpty }
        guard !meaningful.isEmpty else { return nil }
        return try? JSONEncoder().encode(meaningful)
    }

    static func decodeBreaks(_ data: Data?) -> [BreakSpan] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([BreakSpan].self, from: data)) ?? []
    }

    static func encodeBreaks(_ breaks: [BreakSpan]) -> Data? {
        let meaningful = breaks.filter { !$0.isEmpty }
        guard !meaningful.isEmpty else { return nil }
        return try? JSONEncoder().encode(meaningful)
    }
}
