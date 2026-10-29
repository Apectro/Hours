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
/// - **Leaving with no clock** asks to write today's hours when the site has
///   no day for today yet (`SiteReminderPlan.isWritten`, the evening
///   reminder's rule) and today is not a day off, offering "Same as last
///   day" when there is a last day that copies to something.
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
        /// Leaving with no clock running, and the site's day for today is
        /// already written: nothing to ask.
        case alreadyWritten
    }

    enum Decision: Hashable, Sendable {
        /// Ask about the clock: start it on arriving, stop it on leaving.
        case remind
        /// Leaving with no clock and today not written: "write today's
        /// hours?", with a "Same as last day" button when there is a last
        /// day to copy, otherwise only the tap that opens the site's day.
        case askToWrite(offersSameAsLastDay: Bool)
        case quiet(QuietReason)
    }

    /// What the site holds for today, for leaving with no clock running.
    struct SiteToday: Hashable, Sendable {
        /// Whether the site has a day for today (`SiteReminderPlan.isWritten`).
        var isWritten: Bool
        /// What "Same as last day" would write today
        /// (`SiteRepository.sameAsLastDay`), nil when there is no last day.
        var sameAsLastDay: SiteDay?

        init(isWritten: Bool, sameAsLastDay: SiteDay? = nil) {
            self.isWritten = isWritten
            self.sameAsLastDay = sameAsLastDay
        }

        /// Written already: leaving with no clock asks nothing.
        static let written = SiteToday(isWritten: true)
    }

    static func decide(
        _ event: ArrivalEvent,
        site: Site,
        today: DayComputation,
        isClockRunning: Bool,
        siteToday: SiteToday = .written,
        log: ArrivalReminderLog,
        now: Date
    ) -> Decision {
        guard site.monitorsArrival else { return .quiet(.notWatched) }
        let ask: Decision
        switch event {
        case .arrived:
            if isClockRunning { return .quiet(.clockAlreadyRunning) }
            if isDayOff(today) { return .quiet(.dayOff) }
            ask = .remind
        case .left:
            if isClockRunning {
                ask = .remind
            } else {
                if siteToday.isWritten { return .quiet(.alreadyWritten) }
                if isDayOff(today) { return .quiet(.dayOff) }
                let copies = siteToday.sameAsLastDay.map { !$0.isBlank } ?? false
                ask = .askToWrite(offersSameAsLastDay: copies)
            }
        }
        // One two hours for each way, whichever question leaving asks.
        if let last = log.lastReminder(event, siteID: site.id), abs(now.timeIntervalSince(last)) < cooldown {
            return .quiet(.askedRecently)
        }
        return ask
    }

    /// The last day's start and end, for "07:00–15:30 like last time"; nil
    /// when it has no day or not both times.
    static func lastTimes(_ day: SiteDay?) -> (start: TimeOfDay, end: TimeOfDay)? {
        guard let start = day?.start, let end = day?.end else { return nil }
        return (start, end)
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
///
/// It also remembers which sites were asked "write today's hours?" today, so
/// the evening site reminder leaves them out (`SiteReminderPlan.dates`).
struct ArrivalReminderLog: Hashable, Sendable, Codable {
    /// `"<site id>|arrived"` → when that reminder was shown.
    private var entries: [String: Date]
    /// Site id → the date key of the day it was asked to write.
    private var askedToWrite: [String: Int]

    init() {
        entries = [:]
        askedToWrite = [:]
    }

    mutating func recordAskedToWrite(siteID: UUID, on date: CalendarDate) {
        askedToWrite[siteID.uuidString] = date.key
    }

    func sitesAskedToWrite(on date: CalendarDate) -> Set<UUID> {
        Set(askedToWrite.compactMap { $0.value == date.key ? UUID(uuidString: $0.key) : nil })
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
    /// With `today`, also without the write questions of other days.
    func pruned(now: Date, today: CalendarDate? = nil) -> ArrivalReminderLog {
        var copy = self
        copy.entries = entries.filter { abs(now.timeIntervalSince($0.value)) < ArrivalReminderPolicy.cooldown }
        if let today {
            copy.askedToWrite = askedToWrite.filter { $0.value == today.key }
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey { case entries, askedToWrite }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = container.lenient(.entries, [:])
        askedToWrite = container.lenient(.askedToWrite, [:])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        if !askedToWrite.isEmpty { try container.encode(askedToWrite, forKey: .askedToWrite) }
    }
}
