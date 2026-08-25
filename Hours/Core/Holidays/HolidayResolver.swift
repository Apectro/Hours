import Foundation

/// Answers "is this day a holiday, and which one?".
///
/// Occurrences are expanded per year and cached, so a month of calendar cells
/// costs one expansion rather than one rule evaluation per cell.
struct HolidayResolver: Sendable {
    private let rules: [HolidayRule]
    private let index: [Int: [HolidayRule]]

    init(rules: [HolidayRule], calendar: Calendar, years: Set<Int>) {
        let active = rules.filter { $0.isEnabled }
        self.rules = active

        var index: [Int: [HolidayRule]] = [:]
        for year in years {
            for rule in active {
                guard let date = rule.recurrence.occurrence(inYear: year, calendar: calendar) else { continue }
                index[date.key, default: []].append(rule)
            }
        }
        self.index = index
    }

    init(rules: [HolidayRule], calendar: Calendar, covering range: CalendarDateRange) {
        // One extra year on each side so a week or month view that spills over a
        // year boundary still resolves.
        let years = Set((range.start.year - 1)...(range.end.year + 1))
        self.init(rules: rules, calendar: calendar, years: years)
    }

    func holidays(on date: CalendarDate) -> [HolidayRule] {
        index[date.key] ?? []
    }

    /// The holiday that decides the day when several coincide: a working
    /// holiday never suppresses a day off, so paid absence wins.
    func primaryHoliday(on date: CalendarDate) -> HolidayRule? {
        let matches = holidays(on: date)
        if let absence = matches.first(where: { !$0.countsAsWorkingDay }) { return absence }
        return matches.first
    }

    func isHoliday(_ date: CalendarDate) -> Bool {
        index[date.key] != nil
    }

    var allRules: [HolidayRule] { rules }

    static func empty(calendar: Calendar) -> HolidayResolver {
        HolidayResolver(rules: [], calendar: calendar, years: [])
    }
}
