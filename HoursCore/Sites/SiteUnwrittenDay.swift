import Foundation

/// Which days of a site's month are outlined as "nothing written here".
///
/// A weekday of the shown month, before today, with nothing written for the
/// site. Monday to Friday by the calendar's own weekday numbers and nothing
/// cleverer: the site has no schedule of its own to consult, and guessing one
/// would put outlines on days nobody was meant to work. A public holiday is
/// not one of them either.
enum SiteUnwrittenDay {
    static func isUnwritten(
        _ date: CalendarDate,
        isInMonth: Bool,
        today: CalendarDate,
        isWritten: Bool,
        calendar: Calendar,
        holidays: Set<Int> = []
    ) -> Bool {
        guard isInMonth, date < today, !isWritten, !holidays.contains(date.key) else { return false }
        let weekday = date.weekday(in: calendar)
        return weekday != 1 && weekday != 7
    }
}
