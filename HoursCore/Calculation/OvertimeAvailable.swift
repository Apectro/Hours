import Foundation

/// The running balance, read as days off: "+12h 30m · about 1.5 days off".
///
/// A day is the average working day of the week in force on the date asked
/// about — every active job's hours added together, as the balance adds
/// them — so a 9-9-9-9-4 week reads in 8-hour days, which is what a day of
/// time off in lieu would actually take from it on average.
struct OvertimeAvailable: Hashable, Sendable {
    /// The balance itself; always positive.
    var minutes: Int
    /// The length of an average working day.
    var dayMinutes: Int
    /// To the nearest half day. Nil with no working days to measure by.
    var daysOff: HalfDays?

    /// Nil when there is nothing to take: a balance at or below zero.
    init?(balanceMinutes: Int, on date: CalendarDate, settings: AppSettings) {
        guard balanceMinutes > 0 else { return nil }
        let dayMinutes = settings.averageWorkingDayMinutes(on: date)
        self.minutes = balanceMinutes
        self.dayMinutes = dayMinutes
        // Rounded half up, in whole halves: (2b + d/2) / d.
        self.daysOff = dayMinutes > 0
            ? HalfDays(halves: (balanceMinutes * 2 + dayMinutes / 2) / dayMinutes)
            : nil
    }
}

extension AppSettings {
    /// The average contracted day across the weekdays anything is expected
    /// on, in the weeks every active job has in force on `date`. Zero when no
    /// weekday expects anything.
    func averageWorkingDayMinutes(on date: CalendarDate) -> Int {
        let jobs = activeJobs
        let perWeekday = (1...7).map { weekday in
            jobs.reduce(0) { $0 + $1.schedule(on: date).expectedMinutes(forWeekday: weekday) }
        }
        let working = perWeekday.filter { $0 > 0 }
        guard !working.isEmpty else { return 0 }
        return (working.reduce(0, +) + working.count / 2) / working.count
    }
}
