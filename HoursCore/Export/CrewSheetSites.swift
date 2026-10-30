import Foundation

/// Which sites a crew sheet takes in by itself (1.2): every site the crew
/// worked on that month, so a month split between two sites comes out as one
/// sheet without ticking each of them.
enum CrewSheetSites {
    /// The sites to tick for a month, the sheet's own first.
    ///
    /// - Parameters:
    ///   - worked: the month's crew minutes by site; a site with any day
    ///     written is in it, even at zero minutes (a day rained off).
    ///   - order: every site, in the order the list shows them.
    ///   - opened: the site the export was opened from, if any. It stays the
    ///     sheet's own. When it has nothing that month, the sheet is that
    ///     site alone: the other sites' months are not its business.
    /// - Returns: the sites in `order`, `opened` first; empty when nothing
    ///   was worked and no site was opened, so the ticks are left as they are.
    static func ticked(worked: [UUID: Int], order: [UUID], opened: UUID?) -> [UUID] {
        let sites = order.filter { worked[$0] != nil }
        guard let opened else { return sites }
        guard sites.contains(opened) else { return [opened] }
        return [opened] + sites.filter { $0 != opened }
    }

    /// The months the Sites list offers a sheet for: this month and the ones
    /// before it, newest first, that have anything written on any site.
    static func months(worked: Set<YearMonth>, today: CalendarDate, limit: Int) -> [YearMonth] {
        let current = YearMonth(today)
        return (0..<limit)
            .map { current.adding(months: -$0) }
            .filter { worked.contains($0) }
    }
}
