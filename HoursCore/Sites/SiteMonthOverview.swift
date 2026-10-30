import Foundation

/// A site's month at a glance (1.2, mockup Sites): what its card in the
/// Sites list and the top of its own page say, read off the month's
/// `SiteDayStatus`es.
enum SiteMonthOverview {
    /// The status on the right of a site's card.
    enum Headline: Equatable, Sendable {
        /// Work days before today with nothing written: red.
        case notWritten(Int)
        /// Something written this month and nothing missing: green.
        case allWritten
        /// Nothing written and nothing missing: grey.
        case nothingThisMonth
    }

    /// One cell of the card's strip.
    struct StripDay: Equatable, Sendable {
        var date: CalendarDate
        var status: SiteDayStatus
    }

    static func headline(_ statuses: [CalendarDate: SiteDayStatus]) -> Headline {
        let missing = SiteDayStatus.missingCount(in: statuses)
        if missing > 0 { return .notWritten(missing) }
        let written = statuses.values.contains { $0 == .written || $0 == .partly }
        return written ? .allWritten : .nothingThisMonth
    }

    /// The month's work days, in order: every day but the days off, which
    /// are not expected and were not written.
    static func strip(_ statuses: [CalendarDate: SiteDayStatus]) -> [StripDay] {
        statuses
            .filter { $0.value != .dayOff }
            .map { StripDay(date: $0.key, status: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Who each written day of `month` is checked against for
    /// `SiteDayStatus.partly`: this site's visible members, and you, each
    /// from the first day they appear on here, less anyone recorded on
    /// another of your sites that day.
    ///
    /// - `members`: every crew member of every site, hidden ones too: each
    ///   site keeps its own crew, so the same person elsewhere is matched by
    ///   name (`CrewCandidates.key`), as "Add from other sites" matches them.
    ///   Only this site's visible members are checked; someone hidden is no
    ///   longer expected at all.
    /// - `siteDays`: every site's days of the month and as far before it as
    ///   the caller has (at least `SiteWorkDays.lookBackDays`). Someone who
    ///   appears on none of this site's days is never checked.
    ///
    /// A member's join date is the earliest site day listing them, ticked
    /// or given a reason. It is taken on this site: a day on another site
    /// before they first came here never makes this site's days partly, so
    /// the earliest day on any site only matters when it is here.
    ///
    /// On a day, someone is accounted for elsewhere when another site's day
    /// of that date has them ticked present, or gives them a day-type reason
    /// (sick on one site is sick on all). A reason here, "On another site"
    /// included, is the day's own business (`SiteDayStatus.of`).
    static func crew(
        siteID: UUID,
        members: [CrewMember],
        siteDays: [SiteDay],
        month: YearMonth,
        calendar: Calendar
    ) -> SiteCrewCheck {
        let visible = members.filter { $0.siteID == siteID && !$0.isHidden }.map(\.id)
        let candidates = Set(visible).union([CrewMember.youID])

        var joined: [UUID: CalendarDate] = [:]
        for day in siteDays where day.siteID == siteID {
            let listed = day.present.map(\.memberID) + day.absences.map(\.memberID)
            for id in listed where candidates.contains(id) {
                if let known = joined[id], known <= day.date { continue }
                joined[id] = day.date
            }
        }

        // The same people on the other sites, by name; you by your id.
        var keys: [String: [UUID]] = [:]
        for member in members where member.siteID != siteID {
            let key = CrewCandidates.key(for: member.name)
            if !key.isEmpty { keys[key, default: []].append(member.id) }
        }
        var aliases: [UUID: UUID] = [CrewMember.youID: CrewMember.youID]
        for member in members where member.siteID == siteID && joined[member.id] != nil {
            let key = CrewCandidates.key(for: member.name)
            guard !key.isEmpty else { continue }
            for other in keys[key] ?? [] { aliases[other] = member.id }
        }

        let range = month.range(in: calendar)
        var elsewhere: [CalendarDate: Set<UUID>] = [:]
        for day in siteDays where day.siteID != siteID && range.contains(day.date) {
            var there = day.present.map(\.memberID)
            there += day.absences.compactMap { absence in
                if case .dayType = absence.reason { return absence.memberID }
                return nil
            }
            for id in there {
                guard let member = aliases[id], joined[member] != nil else { continue }
                elsewhere[day.date, default: []].insert(member)
            }
        }
        return SiteCrewCheck(joined: joined, elsewhere: elsewhere)
    }

    /// Where a site's month stands on signatures, for its Sign-off row.
    enum SignOffProgress: Equatable, Sendable {
        /// Nobody with hours has signed, or nobody has hours.
        case notYet
        case partial(signed: Int, of: Int)
        case all
    }

    /// Everyone with hours on `siteID` in `month`, and how many of them
    /// signed for the hours they have now. A signature for hours that
    /// changed since does not count.
    static func signOff(
        siteID: UUID,
        month: YearMonth,
        results: [SiteDayResult],
        signatures: [CrewSignature]
    ) -> SignOffProgress {
        var people = Set<UUID>()
        for result in results where result.day.siteID == siteID && result.day.date.yearMonth == month {
            people.formUnion(result.people.map(\.memberID))
        }
        let signed = people.filter { id in
            if case .signed = SignOff.state(for: id, signatures: signatures, results: results, month: month, siteID: siteID) {
                return true
            }
            return false
        }.count
        if people.isEmpty || signed == 0 { return .notYet }
        return signed == people.count ? .all : .partial(signed: signed, of: people.count)
    }
}

/// Who a site's written days are checked against for `SiteDayStatus.partly`
/// (`SiteMonthOverview.crew`): each member from the day they joined, less
/// those accounted for on another site that day.
struct SiteCrewCheck: Hashable, Sendable {
    /// Each member checked, with the first day they appear on the site.
    var joined: [UUID: CalendarDate]
    /// Per day, members recorded on another of your sites.
    var elsewhere: [CalendarDate: Set<UUID>]
    /// Members checked on every day, whatever the date.
    var always: Set<UUID>

    init(joined: [UUID: CalendarDate], elsewhere: [CalendarDate: Set<UUID>] = [:]) {
        self.joined = joined
        self.elsewhere = elsewhere
        self.always = []
    }

    /// `members` on every day: for a caller with no history to go by.
    init(always members: Set<UUID>) {
        self.joined = [:]
        self.elsewhere = [:]
        self.always = members
    }

    /// Nobody: no written day is ever partly.
    static let nobody = SiteCrewCheck(always: [])

    /// The people a written day on `date` must have ticked or given a reason.
    func expected(on date: CalendarDate) -> Set<UUID> {
        let joinedBy = joined.compactMap { $0.value <= date ? $0.key : nil }
        return always.union(joinedBy).subtracting(elsewhere[date] ?? [])
    }
}
