import SwiftUI
import SwiftData

/// One site: its day screen, under the site's name, with the way to the crew
/// and the editor for the site's name, job and archiving in the toolbar.
///
/// Opens on today, or on the date it is given — the personal day editor's
/// "Open on site" passes the day it came from.
struct SiteDetailScreen: View {
    let siteID: UUID
    var initialDate: CalendarDate? = nil

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    // Every site rather than this one: whether this one is read-only depends
    // on the others (see `SiteAccess.isReadOnly`).
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var editing: Site?
    @State private var showsCrew = false

    var body: some View {
        Group {
            if let site {
                SiteDayScreen(
                    site: site,
                    isReadOnly: subscriptions.isReadOnly(site, among: sites),
                    date: initialDate ?? CalendarDate.today(in: settingsStore.workCalendar)
                )
            } else {
                Color.hoursCanvas
            }
        }
        .navigationTitle(site?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The director's sheet export joins these two here.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsCrew = true
                } label: {
                    Label("Crew", systemImage: "person.2")
                }
                .accessibilityIdentifier("site-crew")

                Button("Edit") { editing = site }
                    .disabled(site == nil)
                    .accessibilityIdentifier("site-edit")
            }
        }
        .navigationDestination(isPresented: $showsCrew) {
            CrewScreen(siteID: siteID)
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
