import Foundation

/// A user-defined holiday.
///
/// The app ships with no holidays at all and never guesses a country: public
/// holidays differ by nation, region, employer and year, and a wrong guess is
/// worse than an empty list. The user adds their own, once, and recurring rules
/// carry them forward.
struct HolidayRule: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var recurrence: HolidayRecurrence
    /// When true the day keeps its ordinary contracted hours and is expected to
    /// be worked (a "working holiday"); when false it is paid absence.
    var countsAsWorkingDay: Bool
    var isEnabled: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        recurrence: HolidayRecurrence,
        countsAsWorkingDay: Bool = false,
        isEnabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.recurrence = recurrence
        self.countsAsWorkingDay = countsAsWorkingDay
        self.isEnabled = isEnabled
        self.notes = notes
    }
}

/// When a holiday falls.
///
/// Modelled as a flat struct with a `kind` discriminator rather than an enum
/// with associated values, so it maps one-to-one onto persisted columns and
/// produces a stable, readable shape in JSON backups.
struct HolidayRecurrence: Hashable, Codable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
        /// A single date, never repeated.
        case once
        /// The same month and day every year, e.g. 1 May.
        case annual
        /// The n-th weekday of a month, e.g. the fourth Thursday in November.
        case nthWeekday

        var id: String { rawValue }

        var title: String { label(in: .device) }

        func label(in language: ExportLanguage) -> String {
            switch self {
            case .once: return language(.holidayOnce)
            case .annual: return language(.holidayAnnual)
            case .nthWeekday: return language(.holidayNthWeekday)
            }
        }
    }

    var kind: Kind
    /// Only meaningful for `.once`.
    var year: Int
    var month: Int
    /// Day of month for `.once` and `.annual`.
    var day: Int
    /// 1 = Sunday ... 7 = Saturday, for `.nthWeekday`.
    var weekday: Int
    /// 1...5 for "first"..."fifth", or -1 for "last".
    var ordinal: Int
    /// Optional bounds for recurring rules; `nil` means unbounded.
    var startYear: Int?
    var endYear: Int?

    init(
        kind: Kind,
        year: Int = 2000,
        month: Int = 1,
        day: Int = 1,
        weekday: Int = 2,
        ordinal: Int = 1,
        startYear: Int? = nil,
        endYear: Int? = nil
    ) {
        self.kind = kind
        self.year = year
        self.month = min(max(month, 1), 12)
        self.day = min(max(day, 1), 31)
        self.weekday = min(max(weekday, 1), 7)
        self.ordinal = ordinal == -1 ? -1 : min(max(ordinal, 1), 5)
        self.startYear = startYear
        self.endYear = endYear
    }

    static func once(on date: CalendarDate) -> HolidayRecurrence {
        HolidayRecurrence(kind: .once, year: date.year, month: date.month, day: date.day)
    }

    static func annual(month: Int, day: Int) -> HolidayRecurrence {
        HolidayRecurrence(kind: .annual, month: month, day: day)
    }

    static func nthWeekday(ordinal: Int, weekday: Int, month: Int) -> HolidayRecurrence {
        HolidayRecurrence(kind: .nthWeekday, month: month, weekday: weekday, ordinal: ordinal)
    }

    func isActive(inYear year: Int) -> Bool {
        if let start = startYear, year < start { return false }
        if let end = endYear, year > end { return false }
        return true
    }

    /// The date this rule falls on in `year`, or `nil` if it does not occur.
    ///
    /// A 29 February rule simply does not occur in common years. Silently
    /// moving it to the 28th would invent a holiday the user never entered.
    func occurrence(inYear year: Int, calendar: Calendar) -> CalendarDate? {
        guard isActive(inYear: year) else { return nil }
        switch kind {
        case .once:
            guard year == self.year else { return nil }
            return validated(CalendarDate(year: year, month: month, day: day), calendar: calendar)
        case .annual:
            return validated(CalendarDate(year: year, month: month, day: day), calendar: calendar)
        case .nthWeekday:
            return nthWeekdayOccurrence(inYear: year, calendar: calendar)
        }
    }

    private func validated(_ date: CalendarDate, calendar: Calendar) -> CalendarDate? {
        let length = YearMonth(year: date.year, month: date.month).dayCount(in: calendar)
        return date.day <= length ? date : nil
    }

    private func nthWeekdayOccurrence(inYear year: Int, calendar: Calendar) -> CalendarDate? {
        let month = YearMonth(year: year, month: self.month)
        let length = month.dayCount(in: calendar)
        let firstWeekday = month.firstDay.weekday(in: calendar)
        // Offset from the 1st to the first matching weekday.
        let leadingOffset = (weekday - firstWeekday + 7) % 7
        if ordinal == -1 {
            var lastMatch = 1 + leadingOffset
            while lastMatch + 7 <= length { lastMatch += 7 }
            return CalendarDate(year: year, month: self.month, day: lastMatch)
        }
        let day = 1 + leadingOffset + (ordinal - 1) * 7
        guard day <= length else { return nil }
        return CalendarDate(year: year, month: self.month, day: day)
    }
}
