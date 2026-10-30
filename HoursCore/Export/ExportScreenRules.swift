import Foundation

/// After a sheet goes out: offer to close the month it covered, so its days
/// cannot change by accident once the office has them.
///
/// Only the month just gone, and only while it is open. This month is still
/// running (closing it would refuse today's hours, as the calendar's menu
/// knows: `MonthLock.offer`), and an older month sent again is a correction,
/// not the monthly sheet.
enum ExportCloseOffer {
    /// The month to offer closing after `sent` was shared, or nil.
    static func month(sent: YearMonth?, today: CalendarDate, lock: MonthLock) -> YearMonth? {
        guard let sent, sent == YearMonth(today).adding(months: -1), !lock.isLocked(sent) else { return nil }
        return sent
    }

    /// The month `range` is exactly, first day to last; nil for part of a
    /// month or more than one.
    static func wholeMonth(_ range: CalendarDateRange, calendar: Calendar) -> YearMonth? {
        let month = YearMonth(range.start)
        return range == month.range(in: calendar) ? month : nil
    }
}

extension SiteDayStatus {
    /// The days a sheet of several sites has nothing written for: missing
    /// on one of them and written (even partly) on none. A crew that moved
    /// to the other site for the day is on the sheet that day.
    static func missingDays(merging sites: [[CalendarDate: SiteDayStatus]]) -> [CalendarDate] {
        var missing = Set<CalendarDate>()
        var written = Set<CalendarDate>()
        for statuses in sites {
            for (date, status) in statuses {
                switch status {
                case .missing: missing.insert(date)
                case .written, .partly: written.insert(date)
                case .dayOff, .future: break
                }
            }
        }
        return missing.subtracting(written).sorted()
    }
}

extension ExtraWorkRange {
    /// The whole calendar week before the one holding today, sent or not.
    static func lastWeek(today: CalendarDate, calendar: Calendar) -> ExtraWorkRange {
        let thisWeek = CalendarDateRange.week(containing: today, in: calendar)
        return .dates(CalendarDateRange(
            start: thisWeek.start.adding(days: -7, in: calendar),
            end: thisWeek.start.adding(days: -1, in: calendar)
        ))
    }
}

extension ExtraWorkReport {
    /// How long `jobs` took together: each job once, as long as it took
    /// (`ExtraWorkJob.duration`), however many people were on it.
    static func totalMinutes(of jobs: [ExtraWorkJob]) -> Int {
        jobs.reduce(0) { $0 + $1.duration }
    }
}
