import Foundation

/// The crew days on the Today screen (1.2): a row for each active site
/// that is written today, or expected today and not written yet.
///
/// "Expected" is the Sites list's and the evening reminder's rule
/// (`SiteWorkDays.expects`), decided by the caller; this only shapes the
/// rows, so the Today screen and the Sites list cannot disagree.
enum CrewDayToday {
    struct Row: Hashable, Sendable, Identifiable {
        var siteID: UUID
        var siteName: String
        var isWritten: Bool
        /// Written: how many were there. Not written: the crew offered for
        /// the day, you included.
        var people: Int
        /// The crew's hours, when written.
        var crewMinutes: Int?

        var id: UUID { siteID }
    }

    /// - Parameters:
    ///   - written: each site's day today, where one is stored.
    ///   - expected: the active sites a day is expected on today.
    ///   - coworkers: how many people other than you are on each crew.
    ///   - crewMinutes: the crew's hours on a written day.
    static func rows(
        sites: [Site],
        written: [UUID: SiteDay],
        expected: Set<UUID>,
        coworkers: [UUID: Int],
        crewMinutes: (SiteDay) -> Int
    ) -> [Row] {
        sites
            .filter { !$0.isArchived }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .compactMap { site in
                if let day = written[site.id] {
                    return Row(
                        siteID: site.id, siteName: site.name, isWritten: true,
                        people: day.present.count, crewMinutes: crewMinutes(day)
                    )
                }
                guard expected.contains(site.id) else { return nil }
                return Row(
                    siteID: site.id, siteName: site.name, isWritten: false,
                    people: (coworkers[site.id] ?? 0) + 1, crewMinutes: nil
                )
            }
    }
}
