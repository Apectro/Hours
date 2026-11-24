import Foundation

/// What a site sheet knows about its month beyond the days written
/// (2026-11): the sheet lists every day, as the personal timesheet does, so
/// a director reads the whole month — weekends, public holidays, a pause —
/// and not only the days somebody wrote.
struct SiteSheetMonth: Hashable, Sendable {
    /// The public holidays off, by date, each with its name: the ones the
    /// site's calendar draws (`HolidayResolver.daysOff`). Empty while
    /// holidays are not tracked.
    var holidays: [CalendarDate: String]
    /// Every day of the range has a row. Off, only the days written are
    /// listed, as the sheet was before; a holiday the crew worked keeps its
    /// mark either way.
    var listsEveryDay: Bool

    init(holidays: [CalendarDate: String] = [:], listsEveryDay: Bool = true) {
        self.holidays = holidays
        self.listsEveryDay = listsEveryDay
    }

    /// Only the days written and no holidays: the sheet exactly as it was.
    static let writtenDaysOnly = SiteSheetMonth(listsEveryDay: false)
}

/// What a day nobody wrote is, on a site sheet that lists every day.
enum SiteSheetEmptyDay: Hashable, Sendable {
    /// A public holiday off, by its name.
    case holiday(String)
    /// Not a work day of the site: a weekend, drawn quiet.
    case notAWorkDay
    /// A work day while the site is paused (`SitePause`).
    case paused
    /// A work day with nothing written: left empty. Not an accusation —
    /// this is a printed sheet — and not shaded.
    case notWritten

    /// The weekdays a site is worked, for the sheet: its work days when
    /// they are set, and Monday to Friday when not. Deliberately not the
    /// weekdays it was worked lately, which the reminders go by: a printed
    /// month must not change with the day it is printed on.
    static func workDays(of setup: SiteSetup) -> Set<Int> {
        setup.workDays.isEmpty ? SiteSetup.mondayToFriday : setup.workDays
    }

    /// One day's kind. `setups` are the sheet's sites': with several, a
    /// day is quiet only when none of them works it, and paused only when
    /// every site that does is paused. A holiday comes first, as on the
    /// personal calendar, on a weekend and during a pause too.
    static func of(
        _ date: CalendarDate,
        setups: [SiteSetup],
        holidays: [CalendarDate: String],
        calendar: Calendar
    ) -> SiteSheetEmptyDay {
        if let name = holidays[date] { return .holiday(name) }
        let weekday = date.weekday(in: calendar)
        // A sheet with no site to ask goes by Monday to Friday.
        let working = (setups.isEmpty ? [SiteSetup()] : setups).filter { workDays(of: $0).contains(weekday) }
        if working.isEmpty { return .notAWorkDay }
        if working.allSatisfy({ $0.isPaused(on: date) }) { return .paused }
        return .notWritten
    }
}

extension SiteSheetBuilder {
    /// The row of a day nobody wrote: the date and the day, a dash across
    /// each person's pair, and in the notes what the day was — the
    /// holiday's name, "Paused" — when it was anything.
    ///
    /// - `leading`: the columns before the people (the date and the day,
    ///   and on a sheet for several sites the site, left empty).
    func emptyDayRow(
        _ date: CalendarDate,
        kind: SiteSheetEmptyDay,
        leading: Int,
        people: Int,
        formatter: ReportBuilder
    ) -> ReportRow {
        let language = settings.export.language
        var values = [formatter.dateText(date), formatter.weekdayText(date)]
        values += Array(repeating: "", count: max(0, leading - values.count))
        for _ in 0..<people { values += [emptyPlaceholder, ""] }

        var tint: TypeTint?
        switch kind {
        case let .holiday(name):
            values.append(name)
            tint = ReportDayHighlight.tint(for: settings.dayTypeCatalog.definition(for: .holiday))
        case .paused:
            values.append(language(.sitePaused))
            tint = .gray
        case .notAWorkDay, .notWritten:
            values.append("")
        }

        var isHoliday = false
        if case .holiday = kind { isHoliday = true }
        var row = ReportRow(
            id: date.key,
            values: values,
            minutes: Array(repeating: nil, count: values.count),
            isWorkingDay: kind != .notAWorkDay,
            balanceMinutes: 0,
            hasEntry: false,
            isAbsence: isHoliday,
            mergedGroups: Set((0..<people).map { leading + $0 })
        )
        row.dayTint = tint
        return row
    }

    /// The dates the sheet has a row for: every day of the range, or only
    /// the ones written.
    func listedDates(written: [CalendarDate], range: CalendarDateRange, month: SiteSheetMonth) -> [CalendarDate] {
        month.listsEveryDay ? range.days(in: calendar) : written
    }

    /// A written day's note with the public holiday it fell on leading it:
    /// a holiday the crew worked keeps its name.
    func holidayNote(_ note: String, on date: CalendarDate, month: SiteSheetMonth) -> String {
        guard let name = month.holidays[date] else { return note }
        return note.isEmpty ? name : "\(name) · \(note)"
    }

    /// The date and the day of a written day on a public holiday, shaded in
    /// the holiday's colour: groups 0 and 1.
    func holidayMark(on date: CalendarDate, month: SiteSheetMonth) -> [Int: TypeTint] {
        guard month.holidays[date] != nil,
              let tint = ReportDayHighlight.tint(for: settings.dayTypeCatalog.definition(for: .holiday))
        else { return [:] }
        return [0: tint, 1: tint]
    }

    /// The public holidays of the range, for the closing row that counts
    /// each person's holidays off.
    func holidayDates(in range: CalendarDateRange, month: SiteSheetMonth) -> Set<CalendarDate> {
        Set(month.holidays.keys.filter { range.contains($0) })
    }
}

extension ReportTable {
    /// The days of a site sheet with something written on them, a day on
    /// several sites once: what "21 days" means now that the sheet has a
    /// row for every day of the month.
    var writtenDayCount: Int {
        // A day's first row carries its date key; a further site's row and
        // the day's Total have ids below zero.
        rows.filter { $0.role == .day && $0.hasEntry && $0.id > 0 }.count
    }
}
