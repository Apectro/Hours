import Foundation
import SwiftData

/// A plausible month, for the screenshots that go on the App Store listing.
///
/// Only ever reached behind `-hours-sample-data`, which the UI test target
/// passes and nothing else does. A screenshot of an empty calendar sells
/// nothing, and hand-entering a month on a device to take one is exactly the
/// work this app exists to avoid.
///
/// Deliberately not a demo mode. It writes into the in-memory store the UI
/// tests already use, so it can never touch anyone's real hours.
@MainActor
enum SampleData {
    static let launchArgument = "-hours-sample-data"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// A working month with the shape a real one has: ordinary days, a couple
    /// of long ones, an early finish, a split shift, a week of leave, a public
    /// holiday and a Saturday that was worked.
    static func seed(into repository: WorkdayRepository, calendar: Calendar, today: CalendarDate) {
        let month = today.yearMonth

        repository.upsert(
            HolidayRule(name: "Public holiday", recurrence: .annual(month: month.month, day: 15))
        )

        for day in month.range(in: calendar).days(in: calendar) {
            guard day <= today else { continue }
            let weekday = calendar.component(.weekday, from: day.date(in: calendar))
            let isWeekend = weekday == 1 || weekday == 7

            if day.day >= 8, day.day <= 12 {
                try? repository.save(DayRecord(date: day, dayTypeID: .vacation))
                continue
            }
            if day.day == 15 { continue }   // the holiday resolves itself

            if isWeekend {
                // One worked Saturday, so the overtime figures have something
                // in them and the weekend styling is visible.
                if day.day == 22, weekday == 7 {
                    try? repository.save(
                        DayRecord(date: day, start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 14, minute: 0))
                    )
                }
                continue
            }

            switch day.day % 7 {
            case 0:
                // A split shift: two blocks with the middle of the day off.
                try? repository.save(DayRecord(date: day, shifts: [
                    Shift(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 12, minute: 30)),
                    Shift(start: TimeOfDay(hour: 17, minute: 0), end: TimeOfDay(hour: 20, minute: 0)),
                ]))
            case 3:
                try? repository.save(DayRecord(
                    date: day,
                    start: TimeOfDay(hour: 8, minute: 0),
                    end: TimeOfDay(hour: 18, minute: 15),
                    breaks: [BreakSpan(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 12, minute: 30))],
                    note: "Release day"
                ))
            case 5:
                try? repository.save(DayRecord(
                    date: day,
                    start: TimeOfDay(hour: 8, minute: 0),
                    end: TimeOfDay(hour: 15, minute: 0),
                    breaks: [BreakSpan(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 12, minute: 30))]
                ))
            default:
                try? repository.save(DayRecord(
                    date: day,
                    start: TimeOfDay(hour: 8, minute: 0),
                    end: TimeOfDay(hour: 16, minute: 30),
                    breaks: [BreakSpan(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 12, minute: 30))]
                ))
            }
        }
    }
}
