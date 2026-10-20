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

    /// A site with a crew, for the UI tests of the site day screen. Separate
    /// from the sample month so those tests start from a calendar with
    /// nothing else in it.
    static let siteLaunchArgument = "-hours-sample-site"

    static var isSiteRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(siteLaunchArgument)
    }

    /// Closes the current month, for the test that a closed month refuses
    /// site edits. Settings in a UI test run are an ephemeral copy, so this
    /// never reaches anyone's real lock.
    static let closedMonthLaunchArgument = "-hours-closed-month"

    static var isClosedMonthRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(closedMonthLaunchArgument)
    }

    /// "Kaiserstrasse 12", with Ivan and Marko on the crew and yesterday
    /// written up: the three of you from 07:00 to 15:30 with half an hour's
    /// break, except that Ivan left at 12:00. Yesterday rather than today so
    /// today opens empty, with "Same as last day" to fill it from.
    ///
    /// Also the 3rd and 4th of last month, everyone there, so the export —
    /// which opens on last month — has a sheet to show. Early in a month
    /// rather than late, so neither can be the day before today.
    static func seedSite(into repository: SiteRepository, calendar: Calendar, today: CalendarDate) {
        let site = Site(name: "Kaiserstrasse 12")
        repository.upsert(site)
        let ivan = CrewMember(siteID: site.id, name: "Ivan", sortOrder: 0)
        let marko = CrewMember(siteID: site.id, name: "Marko", sortOrder: 1)
        repository.upsert(ivan)
        repository.upsert(marko)

        try? repository.save(SiteDay(
            siteID: site.id,
            date: today.adding(days: -1, in: calendar),
            start: TimeOfDay(hour: 7, minute: 0),
            end: TimeOfDay(hour: 15, minute: 30),
            breakMinutes: 30,
            present: [
                Attendance(memberID: CrewMember.youID),
                Attendance(memberID: ivan.id, end: TimeOfDay(hour: 12, minute: 0)),
                Attendance(memberID: marko.id),
            ]
        ))

        let lastMonth = today.yearMonth.adding(months: -1)
        for day in [3, 4] {
            try? repository.save(SiteDay(
                siteID: site.id,
                date: CalendarDate(year: lastMonth.year, month: lastMonth.month, day: day),
                start: TimeOfDay(hour: 7, minute: 0),
                end: TimeOfDay(hour: 16, minute: 0),
                breakMinutes: 30,
                present: [
                    Attendance(memberID: CrewMember.youID),
                    Attendance(memberID: ivan.id),
                    Attendance(memberID: marko.id),
                ]
            ))
        }
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
