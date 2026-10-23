import Foundation

/// What the Apple Watch app shows in its App Store screenshots.
///
/// The watch records nothing itself: every figure is the phone's, sent over
/// WatchConnectivity. A watch simulator in CI has no phone paired with it, so
/// it would only ever show "Open Zeitkonto on your iPhone". Behind
/// `launchArgument` the watch app shows this context instead and does not
/// start a session at all, so nothing the phone sends can replace it.
///
/// The figures follow the phone's sample month (`SampleData`): the same site,
/// a rate of €24.50 with a little in surcharges, eight hours expected and a
/// day of 07:00 to 16:00 with half an hour's break. They are worked out from
/// the moment the shot is taken, because the watch shows the real time and a
/// shift that started tomorrow, or a month's pay on the 2nd, would read as
/// made up.
enum WatchSample {
    /// The same argument the phone's sample month uses.
    static let launchArgument = "-hours-sample-data"
    /// With `launchArgument`: the day is written and the clock is stopped,
    /// rather than a shift running.
    static let clockStoppedArgument = "-hours-sample-clock-stopped"

    /// The phone sample's showcase site (`SampleData.showcaseSiteName`).
    static let siteName = "Kaiserstraße 12"

    private static let expectedMinutes = 8 * 60
    /// 07:00 to 16:00 less half an hour.
    private static let writtenDayMinutes = 8 * 60 + 30
    private static let rateCents = 2_450
    private static let currencyCode = "EUR"

    static func context(arguments: [String], at now: Date, calendar: Calendar) -> WatchContext? {
        guard arguments.contains(launchArgument) else { return nil }
        return context(at: now, calendar: calendar, clockRunning: !arguments.contains(clockStoppedArgument))
    }

    static func context(at now: Date, calendar: Calendar, clockRunning: Bool) -> WatchContext {
        let startOfDay = calendar.startOfDay(for: now)
        let seven = calendar.date(byAdding: .hour, value: 7, to: startOfDay) ?? startOfDay
        // Seven o'clock once it is past; before then, a shift a couple of
        // hours old that still began today.
        let started = seven < now ? seven : max(startOfDay, now.addingTimeInterval(-155 * 60))

        let today = clockRunning ? 0 : writtenDayMinutes
        let earlierDays = workdays(beforeDayOf: now, calendar: calendar)
        let monthWorked = earlierDays * writtenDayMinutes + today
        let monthExpected = (earlierDays + 1) * expectedMinutes
        // The hours at the rate, and about four per cent on top for the
        // overtime surcharge on the half hour over each day.
        let monthCents = monthWorked * rateCents / 60 * 104 / 100
        let todayCents = today * rateCents / 60 * 104 / 100

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            isClockRunning: clockRunning,
            clockStartedAt: clockRunning ? started : nil,
            clockJobName: nil,
            todayWorkedMinutes: today,
            todayExpectedMinutes: expectedMinutes,
            monthWorkedMinutes: monthWorked,
            monthExpectedMinutes: monthExpected,
            monthBalanceMinutes: monthWorked - monthExpected,
            showsBalance: true,
            unrecordedDayCount: 0,
            durationStyle: .hoursAndMinutes,
            isUnlocked: true,
            clockSiteName: clockRunning ? siteName : nil,
            earnings: WidgetEarnings(
                currencyCode: currencyCode,
                todayCents: todayCents,
                weekCents: todayCents,
                monthCents: monthCents
            )
        )
        return WatchContext(snapshot: snapshot, handledCommandIDs: [])
    }

    /// Monday to Friday from the 1st up to the day before `now`.
    private static func workdays(beforeDayOf now: Date, calendar: Calendar) -> Int {
        let day = calendar.component(.day, from: now)
        guard day > 1, let first = calendar.dateInterval(of: .month, for: now)?.start else { return 0 }
        return (0..<(day - 1)).reduce(0) { count, offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { return count }
            return calendar.isDateInWeekend(date) ? count : count + 1
        }
    }
}
