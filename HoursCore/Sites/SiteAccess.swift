import Foundation

/// What the free tier allows for sites.
///
/// Like everything Pro, this gates writing and creating, never viewing: a site
/// that is read-only can still be opened, read and exported in the backup.
enum SiteAccess {
    /// The first site is free, so someone can run the whole feature on their
    /// real site before paying.
    static func canAddSite(activeSites: Int, entitlement: Entitlement, at instant: Date) -> Bool {
        activeSites == 0 || entitlement.allows(.multipleSites, at: instant)
    }

    /// Whether a site may be looked at but not changed.
    ///
    /// Without Pro, the one writable site is the active site with the lowest
    /// `sortOrder` (ties broken by identifier, so the answer never depends on
    /// array order). Archived sites are always read-only without Pro:
    /// restoring one would be a way round the limit.
    static func isReadOnly(_ site: Site, activeSites: [Site], entitlement: Entitlement, at instant: Date) -> Bool {
        if entitlement.allows(.multipleSites, at: instant) { return false }
        if site.isArchived { return true }
        let free = activeSites
            .filter { !$0.isArchived }
            .min { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
        return free?.id != site.id
    }
}
