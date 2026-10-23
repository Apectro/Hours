import Foundation

/// The weekly note that finished extra work has not reached the boss yet.
struct ExtraWorkReminder: Hashable, Sendable {
    enum Scope: Hashable, Sendable {
        /// Every waiting job is on this one site: the note names it.
        case site(id: UUID, name: String)
        /// Waiting jobs on this many sites: the note gives the total.
        case sites(Int)
    }

    /// Finished jobs the boss does not have yet, over every site in `scope`.
    let count: Int
    let scope: Scope

    /// Where a tap leads: that site's report, or the Sites tab when there are
    /// several to choose from.
    var link: AppLink {
        switch scope {
        case let .site(id, _): return .siteExtraWork(id)
        case .sites: return .sites
        }
    }
}

/// What the "extra work not sent" reminder says, if anything.
///
/// A local notification cannot look at the store when it fires, so the app
/// asks this whenever the answer could change — the app coming to the front,
/// a job saved, ticked or deleted, a report sent, the setting changed — and
/// replaces the scheduled note with the result, or removes it when this says
/// nothing is waiting.
///
/// Waiting means what the report's "Not sent yet" means (`awaitsReport`),
/// finished jobs only: a job still in progress is not news for the boss.
/// Archived sites are left out, as are jobs whose site is gone.
enum ExtraWorkReminderPlan {
    static func reminder(sites: [Site], jobs: [ExtraWorkJob]) -> ExtraWorkReminder? {
        let active = sites.filter { !$0.isArchived }
        let activeIDs = Set(active.map(\.id))
        let waiting = jobs.filter { $0.isDone && $0.awaitsReport && activeIDs.contains($0.siteID) }
        guard !waiting.isEmpty else { return nil }

        let siteIDs = Set(waiting.map(\.siteID))
        if siteIDs.count == 1, let site = active.first(where: { siteIDs.contains($0.id) }) {
            return ExtraWorkReminder(count: waiting.count, scope: .site(id: site.id, name: site.name))
        }
        return ExtraWorkReminder(count: waiting.count, scope: .sites(siteIDs.count))
    }
}
