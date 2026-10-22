import Foundation
import SwiftData

/// A stored holiday rule. Mirrors `HolidayRule`, decomposed into primitives.
///
/// `identifier` is unique by rule rather than by constraint, for the same
/// reason as `DayEntry.dateKey`.
@Model
final class HolidayRecord {
    var identifier: UUID = UUID()
    var name: String = ""

    /// `HolidayRecurrence.Kind` raw value, or for a movable rule its packed
    /// shape (`easter:1:1:2:39`).
    var kindRawValue: String = HolidayRecurrence.Kind.annual.rawValue
    var year: Int = 2000
    var month: Int = 1
    var day: Int = 1
    var weekday: Int = 2
    var ordinal: Int = 1
    var startYear: Int?
    var endYear: Int?

    var countsAsWorkingDay: Bool = false
    var isEnabled: Bool = true
    var notes: String = ""
    var createdAt: Date = Date()

    init(rule: HolidayRule) {
        self.identifier = rule.id
        self.createdAt = Date()
        apply(rule)
    }
}

extension HolidayRecord {
    var rule: HolidayRule {
        HolidayRule(
            id: identifier,
            name: name,
            recurrence: HolidayRecurrence(stored: StoredHolidayRecurrence(
                kindRawValue: kindRawValue,
                year: year,
                month: month,
                day: day,
                weekday: weekday,
                ordinal: ordinal,
                startYear: startYear,
                endYear: endYear
            )),
            countsAsWorkingDay: countsAsWorkingDay,
            isEnabled: isEnabled,
            notes: notes
        )
    }

    func apply(_ rule: HolidayRule) {
        name = rule.name
        // Movable rules (Easter and the like) pack their shape into the kind
        // string, so 1.0 sees a rule that never occurs. See
        // `HolidayRecurrence.storedColumns`.
        let stored = rule.recurrence.storedColumns
        kindRawValue = stored.kindRawValue
        year = stored.year
        month = stored.month
        day = stored.day
        weekday = stored.weekday
        ordinal = stored.ordinal
        startYear = stored.startYear
        endYear = stored.endYear
        countsAsWorkingDay = rule.countsAsWorkingDay
        isEnabled = rule.isEnabled
        notes = rule.notes
    }
}
