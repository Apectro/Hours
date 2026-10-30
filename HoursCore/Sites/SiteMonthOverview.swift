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

    /// The crew a written day of `month` is checked against for
    /// `SiteDayStatus.partly`: the visible members, and you, who appear on
    /// any of the site's days that month, ticked or given a reason.
    ///
    /// Someone added to the crew later never appears on the older days, so
    /// they do not turn every one of them partly; someone hidden is no
    /// longer expected at all.
    static func crew(
        siteID: UUID,
        visible: [UUID],
        siteDays: [SiteDay],
        month: YearMonth,
        calendar: Calendar
    ) -> Set<UUID> {
        let range = month.range(in: calendar)
        var appearing = Set<UUID>()
        for day in siteDays where day.siteID == siteID && range.contains(day.date) {
            appearing.formUnion(day.present.map(\.memberID))
            appearing.formUnion(day.absences.map(\.memberID))
        }
        let candidates = Set(visible).union([CrewMember.youID])
        return candidates.intersection(appearing)
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
