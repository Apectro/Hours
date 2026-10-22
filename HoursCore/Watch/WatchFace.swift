import Foundation

/// Everything the watch's main screen and its complications show, worked out
/// from the last snapshot the phone sent and the taps it has not answered.
///
/// The figures are the widgets' own accessors, so the wrist cannot disagree
/// with the Home Screen — yesterday's total is not today's, a new month
/// starts at nothing. Taps still waiting for the phone are laid over them, so
/// Clock in on a watch whose phone is in the van shows the clock running at
/// once rather than a button that seems to do nothing. The phone's answer
/// replaces the guess when it comes: it is the phone that records the shift,
/// with its breaks and rounding, which the watch knows nothing about.
///
/// Text here is figures only. Words are the watch's to localize, which the
/// engine cannot do (see ARCHITECTURE, Text and tests).
struct WatchFace: Hashable, Sendable {
    enum Action: Hashable, Sendable {
        case clockIn
        case clockOut
    }

    /// The figure under today's, following the app's main-figure choice.
    enum Secondary: Hashable, Sendable {
        /// The month's balance, signed: "+1:30".
        case balance(String, isBehind: Bool)
        /// The month's earnings, while earnings are the main figure.
        case earnings(String)
        /// The month's hours, when the balance is switched off.
        case monthWorked(String)
    }

    /// False until the phone has sent anything at all.
    var hasData: Bool
    var workedMinutes: Int
    var workedText: String
    /// Nil on a day with nothing expected.
    var expectedText: String?
    /// Today's progress, nil on a day with nothing expected.
    var fraction: Double?
    var isRunning: Bool
    var runningSince: Date?
    /// The site the clock belongs to, or its job; nil when stopped.
    var place: String?
    var secondary: Secondary
    var action: Action
    /// A tap is waiting for the phone.
    var isWaitingForPhone: Bool

    init(snapshot: WidgetSnapshot?, pending: [WatchCommand], at instant: Date, calendar: Calendar) {
        let snapshot = snapshot ?? .empty
        hasData = snapshot.generatedAt != .distantPast
        isWaitingForPhone = !pending.isEmpty

        // Today without the clock, then the clock, then whatever the
        // waiting taps did to it in the order they were made.
        let recorded = snapshot.describesDay(of: instant, calendar: calendar) ? snapshot.todayWorkedMinutes : 0
        var since: Date? = snapshot.isClockRunning ? snapshot.clockStartedAt : nil
        var stoppedMinutes = 0
        for command in pending.sorted(by: { $0.issuedAt < $1.issuedAt }) {
            switch command.kind {
            case .clockIn where since == nil:
                since = command.issuedAt
            case .clockOut:
                if let start = since {
                    stoppedMinutes += Self.minutes(from: start, to: command.issuedAt)
                }
                since = nil
            default:
                break
            }
        }
        let runningMinutes = since.map { Self.minutes(from: $0, to: instant) } ?? 0

        let formatting = snapshot.formatting
        workedMinutes = recorded + stoppedMinutes + runningMinutes
        workedText = formatting.string(workedMinutes)

        let expected = snapshot.expectedMinutes(at: instant, calendar: calendar)
        expectedText = expected > 0 ? formatting.string(expected) : nil
        fraction = expected > 0 ? Double(workedMinutes) / Double(expected) : nil

        isRunning = since != nil
        runningSince = since
        place = since == nil ? nil : (snapshot.clockSiteName ?? snapshot.clockJobName)
        action = since == nil ? .clockIn : .clockOut

        if let cents = snapshot.monthEarnings(at: instant, calendar: calendar), let money = snapshot.money {
            secondary = .earnings(money.string(cents))
        } else if snapshot.showsBalance {
            let balance = snapshot.monthBalance(at: instant, calendar: calendar)
            secondary = .balance(formatting.signedString(balance), isBehind: balance < 0)
        } else {
            secondary = .monthWorked(formatting.string(snapshot.monthWorked(at: instant, calendar: calendar)))
        }
    }

    private static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start)) / 60)
    }
}
