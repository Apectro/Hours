import Foundation

/// Where a day's worked hours came from (2026-11-24): so many minutes on
/// each site, and so many of your own, written on the day itself.
///
/// Read off the resolved day, as `DaySiteSplit` is, and made to add up to
/// the day's own worked minutes exactly: the month grid's bar, its filter
/// and "Sites 112h · Own 16h 30m" are the same hours the totals count, by
/// another cut. A site's part is what its shift worked. What the day has
/// beyond its shifts (rounding, travel counted as work, a figure typed in)
/// is your own when there is anything of your own on the day, and the last
/// site's otherwise.
struct DaySources: Hashable, Sendable {
    /// One site's part of the day.
    struct SitePart: Hashable, Sendable {
        var siteID: UUID
        var minutes: Int
    }

    var date: CalendarDate
    /// The sites with hours on the day, in the order worked, each once.
    var sites: [SitePart]
    /// Hours that are on no site.
    var ownMinutes: Int

    var siteMinutes: Int { sites.reduce(0) { $0 + $1.minutes } }
    /// The day's worked minutes, exactly.
    var totalMinutes: Int { siteMinutes + ownMinutes }
    var isEmpty: Bool { totalMinutes == 0 }

    func minutes(on siteID: UUID) -> Int {
        sites.first { $0.siteID == siteID }?.minutes ?? 0
    }

    /// What the day shows under a filter.
    func minutes(for filter: SourceFilter) -> Int {
        switch filter {
        case .all: return totalMinutes
        case let .site(id): return minutes(on: id)
        case .own: return ownMinutes
        }
    }

    static func make(_ day: DayComputation) -> DaySources {
        var order: [UUID] = []
        var bySite: [UUID: Int] = [:]
        var own = 0
        var hasOwnShift = false
        for shift in day.shifts {
            if let siteID = shift.siteID {
                if bySite[siteID] == nil { order.append(siteID) }
                bySite[siteID, default: 0] += shift.workedMinutes
            } else {
                hasOwnShift = true
                own += shift.workedMinutes
            }
        }

        // The day's total is the one figure everything else counts; the
        // shifts are made to agree with it.
        let total = max(0, day.workedMinutes)
        var difference = total - (own + bySite.values.reduce(0, +))
        let ownTakesIt = hasOwnShift || day.countedTravelMinutes > 0 || order.isEmpty
        if ownTakesIt {
            let adjusted = max(0, own + difference)
            difference -= adjusted - own
            own = adjusted
        }
        // Whatever is left goes on, or comes off, the last site first.
        for siteID in order.reversed() where difference != 0 {
            let before = bySite[siteID] ?? 0
            let adjusted = max(0, before + difference)
            difference -= adjusted - before
            bySite[siteID] = adjusted
        }
        // More to take off than the sites had: your own gives the rest.
        if difference < 0 { own = max(0, own + difference) }

        return DaySources(
            date: day.date,
            sites: order.compactMap { siteID in
                let minutes = bySite[siteID] ?? 0
                return minutes > 0 ? SitePart(siteID: siteID, minutes: minutes) : nil
            },
            ownMinutes: own
        )
    }
}

/// The month's filter chips: All, one site, or your own hours.
enum SourceFilter: Hashable, Sendable {
    case all
    case site(UUID)
    case own
}

/// A period's worked hours by where they came from: the summary's "Sites
/// 112h · Own 16h 30m", the chips to offer and what a filter leaves.
///
/// Counted by the rule the period's Worked is counted by
/// (`DayComputation.counts(through:)`), so `totalMinutes` is that figure.
struct PeriodSources: Hashable, Sendable {
    /// Each counted day with hours, by date key.
    var days: [Int: DaySources]
    /// Minutes by site, over the period.
    var minutesBySite: [UUID: Int]
    var ownMinutes: Int

    var siteMinutes: Int { minutesBySite.values.reduce(0, +) }
    var totalMinutes: Int { siteMinutes + ownMinutes }

    init(days computations: [DayComputation], countingThrough: CalendarDate? = nil) {
        var days: [Int: DaySources] = [:]
        var bySite: [UUID: Int] = [:]
        var own = 0
        for day in computations where day.counts(through: countingThrough) {
            let sources = DaySources.make(day)
            guard !sources.isEmpty else { continue }
            days[day.date.key] = sources
            for part in sources.sites { bySite[part.siteID, default: 0] += part.minutes }
            own += sources.ownMinutes
        }
        self.days = days
        self.minutesBySite = bySite
        self.ownMinutes = own
    }

    func minutes(for filter: SourceFilter) -> Int {
        switch filter {
        case .all: return totalMinutes
        case let .site(id): return minutesBySite[id] ?? 0
        case .own: return ownMinutes
        }
    }

    /// The chips above the month: All, each of `sites` that is active and
    /// has hours in the period, in the sites' own order, then Own. Empty
    /// when there is no site at all, which is when the row is not shown.
    func filters(sites: [Site]) -> [SourceFilter] {
        guard !sites.isEmpty else { return [] }
        let offered = SitePalette.ordered(sites)
            .filter { !$0.isArchived && (minutesBySite[$0.id] ?? 0) > 0 }
            .map { SourceFilter.site($0.id) }
        return [.all] + offered + [.own]
    }

    /// `filter` while its chip is offered, All otherwise: a site chosen in
    /// one month is not a filter on a month it has no hours in.
    func effective(_ filter: SourceFilter, sites: [Site]) -> SourceFilter {
        filters(sites: sites).contains(filter) ? filter : .all
    }

    /// Each row's week total under a filter, as `CalendarWeekTotals.minutes`
    /// gives it for All (worked and credited): one source's hours are worked
    /// hours only, counted by the same rule.
    static func weekMinutes(
        of layout: MonthLayout,
        days: [DayComputation],
        calendar: Calendar,
        countingThrough: CalendarDate?,
        filter: SourceFilter
    ) -> [Int] {
        guard filter != .all else {
            return CalendarWeekTotals.minutes(of: layout, days: days, calendar: calendar, countingThrough: countingThrough)
        }
        let sources = PeriodSources(days: days, countingThrough: countingThrough)
        return CalendarWeekTotals.weeks(of: layout, calendar: calendar).map { week in
            week.days(in: calendar).reduce(0) { $0 + (sources.days[$1.key]?.minutes(for: filter) ?? 0) }
        }
    }
}

/// A colour per site, stored nowhere: a site's place among all your sites,
/// archived ones too, in their own order, taken round a small palette. The
/// same site is the same colour on every screen, and archiving another
/// site does not change it.
enum SitePalette {
    /// How many colours there are; the views hold that many.
    static let count = 6

    /// Sites in the order the Sites tab keeps them, ties by id so the
    /// order never depends on what a fetch returned first.
    static func ordered(_ sites: [Site]) -> [Site] {
        sites.sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
    }

    /// Each site's palette index, `0..<count`.
    static func indexes(of sites: [Site]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (position, site) in ordered(sites).enumerated() where result[site.id] == nil {
            result[site.id] = position % count
        }
        return result
    }

    /// For a site that is no longer stored: decided by its id alone, so it
    /// is still the same colour every time.
    static func fallbackIndex(for siteID: UUID) -> Int {
        let bytes = withUnsafeBytes(of: siteID.uuid) { Array($0) }
        return bytes.reduce(0) { ($0 &* 31 &+ Int($1)) % 9_973 } % count
    }
}
