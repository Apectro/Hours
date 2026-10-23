import Foundation

/// Where someone not ticked on a site was working instead, when another of
/// your sites says so: a hint the site day shows greyed, never stored until
/// confirmed.
///
/// Each site keeps its own crew, so the same person is a different member on
/// each site. They are matched the way "Add from other sites" matches them
/// (`CrewCandidates.key`): the same name, ignoring case, accents and spacing.
/// You are the same id everywhere.
enum SiteElsewhere {
    /// The other site `memberID` (a member of `siteID`'s crew, or you) was
    /// ticked present on `date`; nil when none, or when the name matches
    /// people on more than one other site that day.
    static func site(
        of memberID: UUID,
        on siteID: UUID,
        date: CalendarDate,
        crew: [CrewMember],
        siteDays: [SiteDay]
    ) -> UUID? {
        let ids: Set<UUID>
        if memberID == CrewMember.youID {
            ids = [CrewMember.youID]
        } else {
            guard let member = crew.first(where: { $0.id == memberID }) else { return nil }
            let key = CrewCandidates.key(for: member.name)
            guard !key.isEmpty else { return nil }
            ids = Set(crew.filter { $0.siteID != siteID && CrewCandidates.key(for: $0.name) == key }.map(\.id))
        }
        let sites = Set(siteDays
            .filter { $0.date == date && $0.siteID != siteID }
            .filter { day in day.present.contains { ids.contains($0.memberID) } }
            .map(\.siteID))
        return sites.count == 1 ? sites.first : nil
    }
}
