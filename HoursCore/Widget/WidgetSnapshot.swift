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

    /// Today's total including whatever the running clock has accumulated.
    func todayIncludingRunningClock(at instant: Date) -> Int {
        todayWorkedMinutes + runningMinutes(at: instant)
    }

    var formatting: DurationFormatting {
        DurationFormatting(style: durationStyle)
    }

    /// Progress towards the expected hours, or nil when nothing is expected —
    /// a weekend, a holiday, a day of leave. A ring sitting at zero on a Sunday
    /// reads as a failure rather than as a day off, so there is no ring.
    func todayFraction(at instant: Date) -> Double? {
        guard todayExpectedMinutes > 0 else { return nil }
        return Double(todayIncludingRunningClock(at: instant)) / Double(todayExpectedMinutes)
    }

    var monthFraction: Double? {
        guard monthExpectedMinutes > 0 else { return nil }
        return Double(monthWorkedMinutes) / Double(monthExpectedMinutes)
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
