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

    /// The site the listing is built around: a supervisor and a crew of five,
    /// on the job every working day of last month and this one so far.
    static let showcaseSiteName = "Kaiserstraße 12"
    static let showcaseCrew = ["Ivan", "Marko", "Luka", "Tomasz", "Jonas"]

    /// A month as the people the app is for actually have them, for the
    /// listing's screenshots.
    ///
    /// The hours come from the sites rather than from personal days, the way
    /// a site supervisor records them: one site day for the whole crew, which
    /// writes your own calendar day in the same step. So the calendar, the
    /// site's month, the director's sheet and Insights all show the same days
    /// — none of them is dressed up separately.
    ///
    /// Last month in full, because the director's sheet opens on it; this
    /// month up to today, with today always written so the day editor and the
    /// site's day card have something in them whichever weekday CI runs on.
    /// Someone leaves early here and there, someone starts late, one person is
    /// off now and then, the first Saturday is a short morning, a few days
    /// go to a second site, and there is a week of leave and a public holiday,
    /// because a month of identical rows looks like a template.
    static func seed(
        workdays: WorkdayRepository,
        sites: SiteRepository,
        calendar: Calendar,
        today: CalendarDate
    ) {
        let site = Site(name: showcaseSiteName, sortOrder: 0)
        sites.upsert(site)
        let crew = showcaseCrew.enumerated().map { index, name in
            CrewMember(siteID: site.id, name: name, sortOrder: index)
        }
        for member in crew { sites.upsert(member) }

        // A second, smaller site for the odd Friday, so the Sites tab is a
        // list and the crew there can be picked from the first one.
        let second = Site(name: "Schulweg 4", sortOrder: 1)
        sites.upsert(second)
        let secondCrew = ["Ivan", "Emre"].enumerated().map { index, name in
            CrewMember(siteID: second.id, name: name, sortOrder: index)
        }
        for member in secondCrew { sites.upsert(member) }

        // Never today: today is written on the site whatever it is.
        let holiday = today.day == 15 ? 16 : 15
        workdays.upsert(
            HolidayRule(name: "Public holiday", recurrence: .annual(month: today.month, day: holiday))
        )

        let thisMonth = today.yearMonth
        let months = [thisMonth.adding(months: -1), thisMonth]
        for month in months {
            var firstSaturdayDone = false
            for day in month.range(in: calendar).days(in: calendar) where day <= today {
                let isToday = day == today
                let weekday = calendar.component(.weekday, from: day.date(in: calendar))

                if month == thisMonth, !isToday {
                    if day.day >= 8, day.day <= 12 {
                        try? workdays.save(DayRecord(date: day, dayTypeID: .vacation))
                        continue
                    }
                    if day.day == holiday { continue }   // the holiday resolves itself
                }

                switch weekday {
                case 1 where !isToday:
                    continue
                case 7 where !isToday:
                    // One short Saturday a month: the surcharge has
                    // something to show, and the weekend styling is visible.
                    guard !firstSaturdayDone else { continue }
                    firstSaturdayDone = true
                    try? sites.save(SiteDay(
                        siteID: site.id,
                        date: day,
                        start: TimeOfDay(hour: 7, minute: 0),
                        end: TimeOfDay(hour: 12, minute: 0),
                        present: [Attendance(memberID: CrewMember.youID)]
                            + crew.prefix(3).map { Attendance(memberID: $0.id) }
                    ))
                    continue
                case 6 where day.day % 3 == 0 && !isToday:
                    // Now and then a Friday on the second site.
                    try? sites.save(SiteDay(
                        siteID: second.id,
                        date: day,
                        start: TimeOfDay(hour: 7, minute: 0),
                        end: TimeOfDay(hour: 13, minute: 30),
                        breakMinutes: 30,
                        present: [Attendance(memberID: CrewMember.youID)]
                            + secondCrew.map { Attendance(memberID: $0.id) }
                    ))
                    continue
                default:
                    break
                }

                try? sites.save(siteDay(on: day, weekday: weekday, site: site, crew: crew))
            }
        }
    }

    /// An ordinary day on the showcase site: 07:00 to 16:00 with half an
    /// hour's break, which is half an hour over a normal day, and Friday ends
    /// at half past one.
    private static func siteDay(on day: CalendarDate, weekday: Int, site: Site, crew: [CrewMember]) -> SiteDay {
        let isFriday = weekday == 6
        var present = [Attendance(memberID: CrewMember.youID)]
        for (index, member) in crew.enumerated() {
            // Jonas, the apprentice, is at college one day in six.
            if index == 4, day.day % 6 == 0 { continue }
            switch (index, day.day % 5) {
            case (2, 2):
                // Luka leaves at noon now and then.
                present.append(Attendance(memberID: member.id, end: TimeOfDay(hour: 12, minute: 0)))
            case (3, 4):
                // Tomasz starts late on the odd morning.
                present.append(Attendance(memberID: member.id, start: TimeOfDay(hour: 9, minute: 0)))
            default:
                present.append(Attendance(memberID: member.id))
            }
        }
        return SiteDay(
            siteID: site.id,
            date: day,
            start: TimeOfDay(hour: 7, minute: 0),
            end: isFriday ? TimeOfDay(hour: 13, minute: 30) : TimeOfDay(hour: 16, minute: 0),
            breakMinutes: 30,
            present: present
        )
    }

    /// What the screenshots' user is paid: a rate, a quarter more after a
    /// normal day, and the usual weekend and night surcharges. Set since
    /// always, so every sample day earns. A name for the sheets, too, so the
    /// director's sheet does not say "You" at the top.
    static func applyPay(to settings: inout AppSettings) {
        settings.changePay(
            forJob: settings.primaryJob.id,
            to: PayRules(
                hourlyRateCents: 2_450,
                overtimeMode: .afterDailyHours,
                overtimePercent: 25,
                saturdayPercent: 25,
                sundayAndHolidayPercent: 50,
                nightPercent: 25
            ),
            from: nil
        )
        settings.export.ownerName = "Alex Berger"
    }
}
