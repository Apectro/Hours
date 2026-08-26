import Foundation

/// What to do to every day in a range.
enum BulkAction: Hashable, Sendable {
    /// Mark the days as a type — a fortnight of leave, a week off sick.
    case setDayType(DayTypeID)
    /// Fill the days with the working pattern from the schedule.
    case applyWorkingPattern
    /// Remove everything recorded on those days.
    case clear

    var isDestructive: Bool {
        if case .clear = self { return true }
        return false
    }
}

/// A bulk edit, described before it is applied.
struct BulkEditRequest: Hashable, Sendable {
    var range: CalendarDateRange
    var action: BulkAction
    /// Leave weekends and other zero-hour days alone. On by default, because
    /// "two weeks off" almost never means "and also the Saturdays".
    var skipsNonWorkingDays: Bool = true
    /// Days that already have something recorded are left alone unless this is
    /// on, so a bulk edit cannot quietly destroy hours already entered.
    var overwritesExistingEntries: Bool = false
}

/// What a bulk edit would do.
///
/// Computed before anything is written so the sheet can say "12 days, 2 left
/// alone" rather than asking the user to trust it.
struct BulkEditPlan: Hashable, Sendable {
    var changes: [DayRecord]
    var deletions: [CalendarDate]
    var skippedExisting: Int
    var skippedNonWorking: Int

    var affectedDayCount: Int { changes.count + deletions.count }
    var isEmpty: Bool { affectedDayCount == 0 }
}

/// Works out what a bulk edit changes, without touching storage.
enum BulkEditor {
    static func plan(
        _ request: BulkEditRequest,
        existing: [Int: DayRecord],
        settings: AppSettings,
        calendar: Calendar,
        holidays: [HolidayRule] = []
    ) -> BulkEditPlan {
        var changes: [DayRecord] = []
        var deletions: [CalendarDate] = []
        var skippedExisting = 0
        var skippedNonWorking = 0

        let catalog = settings.dayTypeCatalog
        let resolver = HolidayResolver(rules: holidays, calendar: calendar, covering: request.range)

        for date in request.range.days(in: calendar) {
            let weekday = date.weekday(in: calendar)
            let contracted = settings.contractedMinutes(forWeekday: weekday)

            if request.skipsNonWorkingDays && contracted == 0 {
                skippedNonWorking += 1
                continue
            }

            let current = existing[date.key]
            let hasSomething = current.map { !$0.isBlank } ?? false
            if hasSomething && !request.overwritesExistingEntries {
                skippedExisting += 1
                continue
            }

            switch request.action {
            case .clear:
                if hasSomething { deletions.append(date) }

            case let .setDayType(id):
                var record = current ?? DayRecord(date: date)
                record.dayTypeID = id
                // A day of leave has no hours in it. Keeping them would both
                // credit the absence and count the work, which pays the day
                // twice.
                //
                // Hours reach a day by two routes, and this cleared only one.
                // A figure typed by hand — what "Calculate worked hours" off
                // produces — survived being marked as leave, so a fortnight
                // bulk-set to Vacation came back as a fortnight of overtime on
                // days nobody worked. The shifts were gone from the screen, so
                // there was nothing left to explain the number.
                if !catalog.definition(for: id).showsTimesByDefault {
                    record.shifts = []
                    record.manualWorkedMinutes = nil
                }
                changes.append(record)

            case .applyWorkingPattern:
                // Holidays keep their meaning: filling a fortnight with the
                // working pattern should not quietly overwrite a public holiday
                // sitting in the middle of it.
                if settings.features.trackHolidays,
                   let holiday = resolver.primaryHoliday(on: date),
                   !holiday.countsAsWorkingDay {
                    skippedNonWorking += 1
                    continue
                }
                var record = current ?? DayRecord(date: date)
                record.dayTypeID = nil
                record.shifts = [defaultShift(for: settings)]
                changes.append(record)
            }
        }

        return BulkEditPlan(
            changes: changes,
            deletions: deletions,
            skippedExisting: skippedExisting,
            skippedNonWorking: skippedNonWorking
        )
    }

    private static func defaultShift(for settings: AppSettings) -> Shift {
        let schedule = settings.primarySchedule
        return Shift(
            start: schedule.defaultStart,
            end: schedule.defaultEnd,
            breaks: settings.features.trackBreaks && schedule.defaultBreakMinutes > 0
                ? [BreakSpan.duration(schedule.defaultBreakMinutes)]
                : [],
            jobID: settings.tracksMultipleJobs ? settings.primaryJob.id : nil
        )
    }
}
