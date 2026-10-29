import Foundation

/// Reaching or leaving a site the phone watches (1.2).
enum ArrivalEvent: String, Codable, Hashable, Sendable, CaseIterable {
    case arrived
    case left
}

/// Whether reaching or leaving a site should ask about the clock, and which
/// sites the phone watches at all.
///
/// The most common miss in a timesheet is forgetting to start or stop the
/// clock; a question at the gate fixes that. It must never become noise, so
/// it is asked only when the answer could be yes:
///
/// - **Arriving** asks to start the clock only when none is running, and
///   never on a day of absence or a public holiday — a vacation day spent
///   fetching a tool is not a shift. A weekend is not absence: someone at
///   the site on a Saturday is there to work.
/// - **Leaving** asks to stop the clock only while one is running, whatever
///   the day: a clock running on a holiday is hours being worked.
/// - The same question about the same site is not asked twice within two
///   hours (`cooldown`), so a phone hovering on the edge of the circle, or a
///   trip to the van, does not ask again. Each way is counted on its own, so
///   arriving at seven does not silence leaving at half past eight.
///
/// The app gathers the inputs — the site, today resolved by `PeriodEngine`,
/// the running clock, the log — and posts what this decides.
enum ArrivalReminderPolicy {
    /// iOS watches at most 20 regions for one app.
    static let maximumWatchedSites = 20
    static let cooldown: TimeInterval = 2 * 3600
    /// How old an arrival or departure may be and still say when the clock
    /// started or stopped. A notification answered later than this is
    /// about a different stretch of the day.
    static let eventStaleness: TimeInterval = 12 * 3600
    /// Every watched region's identifier starts with this, so the app's
    /// regions can be told from anything else iOS lists.
    static let regionPrefix = "arrival-"

    enum QuietReason: Hashable, Sendable {
        /// The switch is off, the place cleared or the site archived since
        /// the region was set up.
        case notWatched
        case askedRecently
        case dayOff
        case clockAlreadyRunning
        case noClockRunning
    }

    enum Decision: Hashable, Sendable {
        case remind
        case quiet(QuietReason)
    }

    static func decide(
        _ event: ArrivalEvent,
        site: Site,
        today: DayComputation,
        isClockRunning: Bool,
        log: ArrivalReminderLog,
        now: Date
    ) -> Decision {
        guard site.monitorsArrival else { return .quiet(.notWatched) }
        switch event {
        case .arrived:
            if isClockRunning { return .quiet(.clockAlreadyRunning) }
            if isDayOff(today) { return .quiet(.dayOff) }
        case .left:
            if !isClockRunning { return .quiet(.noClockRunning) }
        }
        if let last = log.lastReminder(event, siteID: site.id), abs(now.timeIntervalSince(last)) < cooldown {
            return .quiet(.askedRecently)
        }
        return .remind
    }

    /// A day nobody is due at work by what is marked on it: a public
    /// holiday, paid absence (vacation, sick, bad weather, …), time off in
    /// lieu, or a day off of the user's own. Work, Other and the weekend are
    /// not, and neither is a custom type that is scheduled like work.
    static func isDayOff(_ day: DayComputation) -> Bool {
        switch day.dayType.id {
        case .work, .weekend, .other:
            return false
        case .timeOffInLieu:
            return true
        default:
            return day.dayType.expectation != .scheduled
        }
    }

    // MARK: - Which sites

    struct Plan: Hashable, Sendable {
        /// In the order the Sites tab lists them, at most
        /// `maximumWatchedSites`.
        var watched: [Site]
        /// Sites with the reminder on that did not fit.
        var leftOut: [Site]
    }

    /// The sites to watch: active, with a place, the switch on; the first
    /// twenty in the Sites tab's order.
    static func plan(sites: [Site]) -> Plan {
        let wanted = sites
            .filter(\.monitorsArrival)
            .sorted { ($0.sortOrder, $0.name, $0.id.uuidString) < ($1.sortOrder, $1.name, $1.id.uuidString) }
        return Plan(
            watched: Array(wanted.prefix(maximumWatchedSites)),
            leftOut: Array(wanted.dropFirst(maximumWatchedSites))
        )
    }

    static func regionIdentifier(for siteID: UUID) -> String {
        regionPrefix + siteID.uuidString
    }

    static func siteID(fromRegionIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(regionPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(regionPrefix.count)))
    }

    // MARK: - When

    /// When Start or Stop on the notification puts the clock: when you
    /// arrived or left, which is what the shift was, rather than when the
    /// button was tapped. Now instead when there is no such moment, when it
    /// is in the future, older than `eventStaleness`, or before `notBefore`
    /// (the running clock's start, for a stop).
    static func clockInstant(eventAt event: Date?, now: Date, notBefore: Date? = nil) -> Date {
        guard let event, event <= now, now.timeIntervalSince(event) <= eventStaleness else { return now }
        if let notBefore, event < notBefore { return now }
        return event
    }
}

/// When each site last asked, each way, so the same question is not asked
/// twice within two hours. Kept on this phone only (region events are this
/// phone's), never in settings or a backup.
struct ArrivalReminderLog: Hashable, Sendable, Codable {
    /// `"<site id>|arrived"` → when that reminder was shown.
    private var entries: [String: Date]

    init() {
        entries = [:]
    }

    private static func key(_ event: ArrivalEvent, _ siteID: UUID) -> String {
        siteID.uuidString + "|" + event.rawValue
    }

    func lastReminder(_ event: ArrivalEvent, siteID: UUID) -> Date? {
        entries[Self.key(event, siteID)]
    }

    mutating func record(_ event: ArrivalEvent, siteID: UUID, at instant: Date) {
        entries[Self.key(event, siteID)] = instant
    }

    /// Without what can no longer silence anything, so the log stays a
    /// handful of entries however many sites come and go.
    func pruned(now: Date) -> ArrivalReminderLog {
        var copy = self
        copy.entries = entries.filter { abs(now.timeIntervalSince($0.value)) < ArrivalReminderPolicy.cooldown }
        return copy
    }

    private enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = container.lenient(.entries, [:])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}
