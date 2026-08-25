import Foundation
import SwiftData

/// A stored holiday rule. Mirrors `HolidayRule`, decomposed into primitives.
@Model
final class HolidayRecord {
    @Attribute(.unique) var identifier: UUID = UUID()
    var name: String = ""

    /// `HolidayRecurrence.Kind` raw value.
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
            recurrence: HolidayRecurrence(
                kind: HolidayRecurrence.Kind(rawValue: kindRawValue) ?? .annual,
                year: year,
                month: month,
                day: day,
                weekday: weekday,
                ordinal: ordinal,
                startYear: startYear,
                endYear: endYear
            ),
            countsAsWorkingDay: countsAsWorkingDay,
            isEnabled: isEnabled,
            notes: notes
        )
    }

    func apply(_ rule: HolidayRule) {
        name = rule.name
        kindRawValue = rule.recurrence.kind.rawValue
        year = rule.recurrence.year
        month = rule.recurrence.month
        day = rule.recurrence.day
        weekday = rule.recurrence.weekday
        ordinal = rule.recurrence.ordinal
        startYear = rule.recurrence.startYear
        endYear = rule.recurrence.endYear
        countsAsWorkingDay = rule.countsAsWorkingDay
        isEnabled = rule.isEnabled
        notes = rule.notes
    }
}
