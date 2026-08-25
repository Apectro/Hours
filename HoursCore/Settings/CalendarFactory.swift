import Foundation

extension CalendarPreferences {
    /// The `Calendar` every part of the app shares.
    ///
    /// Built from the device locale and time zone, with the user's
    /// "week starts on" preference applied. Everything that touches dates takes
    /// this as a parameter rather than reaching for `Calendar.current`, which
    /// is what lets tests pin a locale, a zone and a first weekday.
    func makeCalendar(locale: Locale = .current, timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday(in: locale)
        // Matches the ISO definition used by most European contracts and is the
        // conventional choice for week-based reporting.
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}
