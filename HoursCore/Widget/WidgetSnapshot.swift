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
        durationStyle: .hoursAndMinutes
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

    private enum CodingKeys: String, CodingKey {
        case generatedAt, isClockRunning, clockStartedAt, clockJobName
        case todayWorkedMinutes, todayExpectedMinutes
        case monthWorkedMinutes, monthExpectedMinutes, monthBalanceMinutes
        case showsBalance, unrecordedDayCount, durationStyle
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
            durationStyle: container.lenient(.durationStyle, DurationStyle.hoursAndMinutes)
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
        durationStyle: DurationStyle
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
    }
}
