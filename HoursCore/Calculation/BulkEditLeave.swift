import Foundation

extension BulkEditPlan {
    /// `records` as they will be once this plan is applied: its changes
    /// written over them and its deletions removed.
    func applied(to records: [Int: DayRecord]) -> [Int: DayRecord] {
        var result = records
        for record in changes { result[record.date.key] = record }
        for date in deletions { result.removeValue(forKey: date.key) }
        return result
    }
}

/// "Leave left after: 8 days" under a range edit (1.2): the leave year's
/// balance with the plan applied, by the same calculator the day editor's
/// "Vacation left after this" uses.
enum BulkEditLeave {
    /// The vacation left in the leave year holding `date` once `plan` is
    /// applied. `records` are the stored days of that leave year.
    static func remaining(
        after plan: BulkEditPlan,
        on date: CalendarDate,
        records: [Int: DayRecord],
        engine: PeriodEngine,
        holidays: [HolidayRule],
        today: CalendarDate
    ) -> HalfDays {
        let settings = engine.settings
        let calendar = engine.calendar
        let leaveYear = settings.leave.leaveYear(containing: date, calendar: calendar)
        let range = settings.leave.range(ofLeaveYear: leaveYear, calendar: calendar)
        let days = engine.days(in: range, records: plan.applied(to: records), holidays: holidays)
        return LeaveCalculator.balance(
            leaveYear: leaveYear,
            days: days,
            settings: settings,
            calendar: calendar,
            today: today
        ).remaining
    }
}
