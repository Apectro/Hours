import SwiftUI

// Where the paywall is asked for, and what marks the door.
//
// The gate itself is a plain `subscriptions.allows(_:)` at each call site
// rather than a wrapper: the check is one line, and reading it in place beats
// following an abstraction to find out what is being sold.

extension View {
    /// Presents the paywall whenever a gate writes a reason into the binding.
    func paywall(for request: Binding<ProFeature?>) -> some View {
        sheet(item: request) { feature in
            PaywallSheet(reason: feature)
        }
    }

    /// The lock that appears beside something a gate will stop.
    ///
    /// Shown rather than disabling the control: a greyed-out button says "not
    /// for you" and nothing else, where a lock says there is a door.
    @ViewBuilder
    func proLock(_ shows: Bool) -> some View {
        if shows {
            HStack(spacing: Metrics.small) {
                self
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Zeitkonto Pro")
            }
        } else {
            self
        }
    }
}

// MARK: - Sites

extension SubscriptionStore {
    /// The `.multipleSites` gate, asked where a site is added or brought back
    /// from the archive.
    ///
    /// Not a bare `allows(.multipleSites)` like the other gates, because the
    /// first site is free: what is sold is the second *active* one, so the
    /// answer depends on how many are active right now. `SiteAccess` holds
    /// that rule and this only supplies the entitlement and the moment.
    func canAddSite(activeSites: Int) -> Bool {
        SiteAccess.canAddSite(activeSites: activeSites, entitlement: entitlement, at: Date())
    }

    /// Whether a site can be read but not changed: one of the extra sites
    /// after Pro lapsed. Nothing on it is lost, and it opens as usual.
    func isReadOnly(_ site: Site, among sites: [Site]) -> Bool {
        SiteAccess.isReadOnly(
            site,
            activeSites: sites.filter { !$0.isArchived },
            entitlement: entitlement,
            at: Date()
        )
    }
}
