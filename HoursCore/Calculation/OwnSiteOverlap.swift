import Foundation

/// Hours of your own that cover time a site day already has (2026-11-24):
/// what the day editor warns about before saving, "11:30–12:30 overlaps
/// Jarunski Dvori (07:00–12:00)".
///
/// The same pairs `WorkdayCalculator` counts once (`sharedMinutes`): a block
/// of your own within one day, against a site's times that day. The engine
/// already takes the shared minutes off your own block, so saving is safe;
/// this names the block and the site so the time can be put right.
struct OwnSiteOverlap: Hashable, Sendable {
    /// Your own block.
    var ownStart: TimeOfDay
    var ownEnd: TimeOfDay
    /// The site it runs into, and that site's times.
    var siteID: UUID
    var siteStart: TimeOfDay
    var siteEnd: TimeOfDay
    /// How long the two share.
    var sharedMinutes: Int

    /// One entry for each of your own blocks and each site it overlaps, in
    /// the order the blocks are in, then by the site's start.
    static func find(in shifts: [Shift]) -> [OwnSiteOverlap] {
        let sites: [(id: UUID, start: TimeOfDay, end: TimeOfDay)] = shifts.compactMap { shift in
            guard let siteID = shift.siteID, let start = shift.start, let end = shift.end,
                  end.minutes > start.minutes else { return nil }
            return (siteID, start, end)
        }.sorted { $0.start.minutes < $1.start.minutes }
        guard !sites.isEmpty else { return [] }

        var found: [OwnSiteOverlap] = []
        for shift in shifts where shift.siteID == nil {
            // A block past midnight is left alone, as the calculator leaves it.
            guard let start = shift.start, let end = shift.end, end.minutes > start.minutes else { continue }
            for site in sites {
                let shared = min(end.minutes, site.end.minutes) - max(start.minutes, site.start.minutes)
                guard shared > 0 else { continue }
                found.append(OwnSiteOverlap(
                    ownStart: start,
                    ownEnd: end,
                    siteID: site.id,
                    siteStart: site.start,
                    siteEnd: site.end,
                    sharedMinutes: shared
                ))
            }
        }
        return found
    }
}
