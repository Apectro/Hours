import Foundation

/// One person's hours on a site day, resolved from the site's times and their
/// own overrides.
struct PersonDay: Hashable, Sendable {
    var memberID: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int
    var workedMinutes: Int
    /// Mirrors `SiteDay.hasException`: they worked different hours from the site's.
    var isException: Bool
    var warnings: [DayWarning]
}

struct SiteDayResult: Hashable, Sendable {
    var day: SiteDay
    /// Everyone ticked present: you first, then the rest in the order they were ticked.
    var people: [PersonDay]
    var crewTotalMinutes: Int
}

/// Works out what a site day comes to for each person present.
///
/// It does not do its own time arithmetic. Each person becomes a one-shift
/// `DayRecord` and goes through `WorkdayCalculator`'s shift path, then through
/// the user's rounding rule, so DST changes, overnight shifts and rounding
/// behave exactly as they do in the calendar.
struct SiteDayCalculator: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    private let calculator: WorkdayCalculator

    init(settings: AppSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
        self.calculator = WorkdayCalculator(settings: settings, calendar: calendar)
    }

    func compute(_ day: SiteDay) -> SiteDayResult {
        let ordered = day.present.filter { $0.memberID == CrewMember.youID }
            + day.present.filter { $0.memberID != CrewMember.youID }
        let people = ordered.map { personDay(for: $0, in: day) }
        return SiteDayResult(day: day, people: people, crewTotalMinutes: people.reduce(0) { $0 + $1.workedMinutes })
    }

    private func personDay(for attendance: Attendance, in day: SiteDay) -> PersonDay {
        let resolved = day.resolved(for: attendance.memberID)
        let start = resolved?.start
        let end = resolved?.end
        let breakMinutes = resolved?.breakMinutes ?? day.breakMinutes

        let record = DayRecord(
            date: day.date,
            shifts: [Shift(start: start, end: end, breaks: [.duration(breakMinutes)])]
        )
        let definition = settings.dayTypeCatalog.definition(for: .work)
        var warnings: [DayWarning] = []
        let shift = calculator.shiftMinutes(record: record, on: day.date, definition: definition, warnings: &warnings)

        return PersonDay(
            memberID: attendance.memberID,
            start: start,
            end: end,
            breakMinutes: breakMinutes,
            workedMinutes: max(0, settings.rounding.apply(to: shift.workedMinutes)),
            isException: day.hasException(attendance.memberID),
            warnings: warnings
        )
    }
}
