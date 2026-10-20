import SwiftUI
import SwiftData

/// One site.
///
/// A placeholder for now: the day screen of the mockup replaces this body.
/// It already carries what the Sites tab needs to be usable — the way to the
/// crew, and the editor for the site's name, job and archiving.
struct SiteDetailScreen: View {
    let siteID: UUID

    @Environment(SubscriptionStore.self) private var subscriptions

    // Every site rather than this one: whether this one is read-only depends
    // on the others (see `SiteAccess.isReadOnly`).
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var editing: Site?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CrewScreen(siteID: siteID)
                } label: {
                    Label("Crew", systemImage: "person.2")
                }
                .accessibilityIdentifier("site-crew")
            } footer: {
                if let site, subscriptions.isReadOnly(site, among: sites), !site.isArchived {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                }
            }
        }
        .navigationTitle(site?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = site }
                    .disabled(site == nil)
                    .accessibilityIdentifier("site-edit")
            }
        }
        .sheet(item: $editing) { site in
            SiteEditorSheet(
                site: site,
                isNew: false,
                isReadOnly: subscriptions.isReadOnly(site, among: sites),
                otherActiveSites: sites.filter { !$0.isArchived && $0.id != site.id }.count
            )
        }
    }

    /// For display only, so a duplicate row left by sync just means the first
    /// of the two is shown; `SiteRepository` collapses it on the next read.
    private var sites: [Site] {
        var seen = Set<UUID>()
        return siteEntries.map(\.site).filter { seen.insert($0.id).inserted }
    }

    private var site: Site? {
        sites.first { $0.id == siteID }
    }
}
