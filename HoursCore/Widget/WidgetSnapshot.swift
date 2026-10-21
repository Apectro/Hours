import Foundation

/// The handful of figures a widget shows.
///
/// A widget runs in its own process and cannot open the app's database, so the
/// app writes this small file instead. Keeping it to a snapshot rather than
/// sharing the store means the widget never runs a migration, never holds a
/// lock, and cannot be the reason a write fails.
struct WidgetSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var isClockRunning: Bool
    /// When the running clock started, so the widget can show a live figure
    /// without the app having to rewrite the file every minute.
    var clockStartedAt: Date?
    var clockJobName: String?

    var todayWorkedMinutes: Int
    var todayExpectedMinutes: Int
    var monthWorkedMinutes: Int
    var monthExpectedMinutes: Int
    var monthBalanceMinutes: Int
    var showsBalance: Bool

    /// Days in the last fortnight with nothing recorded.
    var unrecordedDayCount: Int

    /// Carried so the widget writes `8:30` or `8.50` exactly as the app does,
    /// rather than picking its own format and looking like a different app.
    var durationStyle: DurationStyle

    /// Whether the widgets are paid for.
    ///
    /// Carried rather than asked, because a widget runs in its own short-lived
    /// process and reaching StoreKit there would mean a network round trip on
    /// every render. The app already knows, and it already writes this file
    /// whenever anything changes.
    var isUnlocked: Bool

    // The redesigned widgets' figures. Each one is optional or empty in a
    // file an earlier version wrote, and the widget simply leaves that part
    // out until the app has run once and written a new one.

    /// The week's bars, for the This week widget.
    var week: WidgetWeek?
    /// A square per working day of the month, for the month widget.
    var monthMarks: [WidgetDayMark]
    /// The site the running clock belongs to, when that is certain.
    var clockSiteName: String?
    /// When today's work is due to end, for "off at 16:30".
    var todayDefaultEnd: TimeOfDay?
    /// The site card, or nil when there is no active site.
    var site: WidgetSite?

    static let empty = WidgetSnapshot(
        generatedAt: .distantPast,
        isClockRunning: false,
        clockStartedAt: nil,
        clockJobName: nil,
        todayWorkedMinutes: 0,
        todayExpectedMinutes: 0,
        monthWorkedMinutes: 0,
        monthExpectedMinutes: 0,
        monthBalanceMinutes: 0,
        showsBalance: true,
        unrecordedDayCount: 0,
        durationStyle: .hoursAndMinutes,
        isUnlocked: false
    )

    /// Elapsed time on the running clock, worked out by the widget itself.
    ///
    /// Nothing when no clock is running, whatever start time the file happens
    /// to carry: a stale one would otherwise read as hours that are still
    /// accruing, and grow for as long as the widget was left alone.
    func runningMinutes(at instant: Date) -> Int {
        guard isClockRunning, let clockStartedAt else { return 0 }
        return max(0, Int(instant.timeIntervalSince(clockStartedAt)) / 60)
    }

    /// Whether the day figures still describe the day `instant` falls in.
    ///
    /// A widget is drawn whenever someone glances at their phone, and only the
    /// app can rewrite this file. Glance at midnight past and the snapshot is
    /// still the one written yesterday evening: its month figures are very
    /// nearly right, and its "today" is a whole day out. Yesterday's eight
    /// hours displayed under the word TODAY is the kind of wrong that is worse
    /// than showing nothing.
    func describesDay(of instant: Date, calendar: Calendar) -> Bool {
        calendar.isDate(generatedAt, inSameDayAs: instant)
    }

    /// Today's total including whatever the running clock has accumulated.
    ///
    /// Once the snapshot is about an earlier day, the stored total is dropped
    /// and only the clock is counted. A clock's elapsed time is measured from
    /// an absolute instant, so it stays true across midnight; the day's total
    /// does not. What is left is right for a new day with nothing yet recorded
    /// — the overwhelmingly common case — and it errs towards showing too
    /// little rather than towards showing yesterday.
    func todayIncludingRunningClock(at instant: Date, calendar: Calendar) -> Int {
        guard describesDay(of: instant, calendar: calendar) else {
            return runningMinutes(at: instant)
        }
        return todayWorkedMinutes + runningMinutes(at: instant)
    }

    /// Expected hours for the day `instant` falls in — nothing once the
    /// snapshot is about an earlier day, since a new day's schedule is not
    /// something this file knows.
    func expectedMinutes(at instant: Date, calendar: Calendar) -> Int {
        describesDay(of: instant, calendar: calendar) ? todayExpectedMinutes : 0
    }

    var formatting: DurationFormatting {
        DurationFormatting(style: durationStyle)
    }

    /// Progress towards the expected hours, or nil when nothing is expected —
    /// a weekend, a holiday, a day of leave. A ring sitting at zero on a Sunday
    /// reads as a failure rather than as a day off, so there is no ring.
    func todayFraction(at instant: Date, calendar: Calendar) -> Double? {
        let expected = expectedMinutes(at: instant, calendar: calendar)
        guard expected > 0 else { return nil }
        return Double(todayIncludingRunningClock(at: instant, calendar: calendar)) / Double(expected)
    }

    /// The same rule one granularity up. Rarer — the first of the month rather
    /// than every night — and just as wrong when it happens.
    func describesMonth(of instant: Date, calendar: Calendar) -> Bool {
        calendar.isDate(generatedAt, equalTo: instant, toGranularity: .month)
    }

    func monthWorked(at instant: Date, calendar: Calendar) -> Int {
        describesMonth(of: instant, calendar: calendar) ? monthWorkedMinutes : 0
    }

    func monthExpected(at instant: Date, calendar: Calendar) -> Int {
        describesMonth(of: instant, calendar: calendar) ? monthExpectedMinutes : 0
    }

    func monthBalance(at instant: Date, calendar: Calendar) -> Int {
        describesMonth(of: instant, calendar: calendar) ? monthBalanceMinutes : 0
    }

    func monthFraction(at instant: Date, calendar: Calendar) -> Double? {
        let expected = monthExpected(at: instant, calendar: calendar)
        guard expected > 0 else { return nil }
        return Double(monthWorked(at: instant, calendar: calendar)) / Double(expected)
    }

    // MARK: - The redesigned widgets

    /// The week's bars as they stand at `instant`, today's with the running
    /// clock in it. Nil once the week is over: Monday morning's widget must
    /// not draw last week's bars under THIS WEEK.
    func weekBars(at instant: Date, calendar: Calendar) -> [WidgetWeekBar]? {
        guard let week, week.workedMinutes.count == 7 else { return nil }
        let today = CalendarDate.today(in: calendar, now: instant)
        let todayIndex = week.start.days(until: today, in: calendar)
        guard (0..<7).contains(todayIndex) else { return nil }

        return week.workedMinutes.enumerated().map { index, stored in
            let isToday = index == todayIndex
            return WidgetWeekBar(
                date: week.start.adding(days: index, in: calendar),
                // Today's bar follows the same rule as the Today widget, so
                // the two never show different figures for the same day.
                minutes: isToday ? todayIncludingRunningClock(at: instant, calendar: calendar) : stored,
                isToday: isToday
            )
        }
    }

    func weekWorked(at instant: Date, calendar: Calendar) -> Int {
        weekBars(at: instant, calendar: calendar)?.reduce(0) { $0 + $1.minutes } ?? 0
    }

    func weekExpected(at instant: Date, calendar: Calendar) -> Int {
        weekBars(at: instant, calendar: calendar) == nil ? 0 : (week?.expectedMinutes ?? 0)
    }

    /// The month's squares as they stand at `instant`.
    ///
    /// Past midnight the file still describes yesterday, so the square that
    /// was today takes the state yesterday's own figures give it and the new
    /// day becomes today. Squares still to come stay that way: nothing in this
    /// file says what happened on them.
    func monthMarks(at instant: Date, calendar: Calendar) -> [WidgetDayMark] {
        guard describesMonth(of: instant, calendar: calendar) else { return [] }
        guard !describesDay(of: instant, calendar: calendar) else { return monthMarks }

        let today = CalendarDate.today(in: calendar, now: instant)
        let yesterday: WidgetDayMark.State = todayWorkedMinutes >= todayExpectedMinutes ? .done : .short
        return monthMarks.map { mark in
            var mark = mark
            if mark.date == today {
                mark.state = .today
            } else if mark.state == .today, mark.date < today {
                mark.state = yesterday
            }
            return mark
        }
    }

    /// Whether the site card's day is written, for the day `instant` falls in.
    func isSiteTodayWritten(at instant: Date, calendar: Calendar) -> Bool {
        describesDay(of: instant, calendar: calendar) && (site?.isTodayWritten ?? false)
    }

    func defaultEnd(at instant: Date, calendar: Calendar) -> TimeOfDay? {
        describesDay(of: instant, calendar: calendar) ? todayDefaultEnd : nil
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, isClockRunning, clockStartedAt, clockJobName
        case todayWorkedMinutes, todayExpectedMinutes
        case monthWorkedMinutes, monthExpectedMinutes, monthBalanceMinutes
        case showsBalance, unrecordedDayCount, durationStyle, isUnlocked
        case week, monthMarks, clockSiteName, todayDefaultEnd, site
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            generatedAt: container.lenient(.generatedAt, .distantPast),
            isClockRunning: container.lenient(.isClockRunning, false),
            clockStartedAt: container.lenientOptional(.clockStartedAt, Date.self),
            clockJobName: container.lenientOptional(.clockJobName, String.self),
            todayWorkedMinutes: container.lenient(.todayWorkedMinutes, 0),
            todayExpectedMinutes: container.lenient(.todayExpectedMinutes, 0),
            monthWorkedMinutes: container.lenient(.monthWorkedMinutes, 0),
            monthExpectedMinutes: container.lenient(.monthExpectedMinutes, 0),
            monthBalanceMinutes: container.lenient(.monthBalanceMinutes, 0),
            showsBalance: container.lenient(.showsBalance, true),
            unrecordedDayCount: container.lenient(.unrecordedDayCount, 0),
            durationStyle: container.lenient(.durationStyle, DurationStyle.hoursAndMinutes),
            isUnlocked: container.lenient(.isUnlocked, false),
            week: container.lenientOptional(.week, WidgetWeek.self),
            monthMarks: container.lenient(.monthMarks, []),
            clockSiteName: container.lenientOptional(.clockSiteName, String.self),
            todayDefaultEnd: container.lenientOptional(.todayDefaultEnd, TimeOfDay.self),
            site: container.lenientOptional(.site, WidgetSite.self)
        )
    }

    init(
        generatedAt: Date,
        isClockRunning: Bool,
        clockStartedAt: Date?,
        clockJobName: String?,
        todayWorkedMinutes: Int,
        todayExpectedMinutes: Int,
        monthWorkedMinutes: Int,
        monthExpectedMinutes: Int,
        monthBalanceMinutes: Int,
        showsBalance: Bool,
        unrecordedDayCount: Int,
        durationStyle: DurationStyle,
        isUnlocked: Bool,
        week: WidgetWeek? = nil,
        monthMarks: [WidgetDayMark] = [],
        clockSiteName: String? = nil,
        todayDefaultEnd: TimeOfDay? = nil,
        site: WidgetSite? = nil
    ) {
        self.generatedAt = generatedAt
        self.isClockRunning = isClockRunning
        self.clockStartedAt = clockStartedAt
        self.clockJobName = clockJobName
        self.todayWorkedMinutes = todayWorkedMinutes
        self.todayExpectedMinutes = todayExpectedMinutes
        self.monthWorkedMinutes = monthWorkedMinutes
        self.monthExpectedMinutes = monthExpectedMinutes
        self.monthBalanceMinutes = monthBalanceMinutes
        self.showsBalance = showsBalance
        self.unrecordedDayCount = unrecordedDayCount
        self.durationStyle = durationStyle
        self.isUnlocked = isUnlocked
        self.week = week
        self.monthMarks = monthMarks
        self.clockSiteName = clockSiteName
        self.todayDefaultEnd = todayDefaultEnd
        self.site = site
    }
}
