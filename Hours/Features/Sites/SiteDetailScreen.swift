import SwiftUI
import SwiftData

/// One site: its month and day screen under the site's name, with the crew,
/// the export and the editor for the site's name, job and archiving folded
/// into one menu in the toolbar.
///
/// Opens on today, or on the date it is given — the personal day editor's
/// "Open on site" passes the day it came from.
struct SiteDetailScreen: View {
    let siteID: UUID
    var initialDate: CalendarDate? = nil
    /// See `SiteRoute.appliesSameAsLastDay`.
    var appliesSameAsLastDay = false
    /// See `SiteRoute.exportMonth`.
    var exportMonth: YearMonth? = nil

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.openSiteCrew) private var openSiteCrew

    // Every site rather than this one: whether this one is read-only depends
    // on the others (see `SiteAccess.isReadOnly`).
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var editing: Site?
    @State private var exporting: Site?
    @State private var readingDiary: Site?
    /// The month the export opens on; `nil` is last month, as the menu does.
    @State private var exportingMonth: YearMonth?
    /// The link's export is opened once. Coming back to the site from the
    /// sheet must not open it again.
    @State private var openedLinkedExport = false

    var body: some View {
        Group {
            if let site {
                SiteDayScreen(
                    site: site,
                    isReadOnly: subscriptions.isReadOnly(site, among: sites),
                    date: initialDate ?? CalendarDate.today(in: settingsStore.workCalendar),
                    appliesSameAsLastDay: appliesSameAsLastDay
                )
            } else {
                Color.hoursCanvas
            }
        }
        .navigationTitle(site?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Pushed by value onto whichever stack this screen is in
                    // (the Sites tab, or the day editor that opened it): a
                    // presented-binding destination here is what once left
                    // the app never going idle. A NavigationLink cannot sit
                    // in a Menu, so the stack's root hands down the push.
                    Button {
                        openSiteCrew(SiteCrewRoute(siteID: siteID))
                    } label: {
                        Label("Crew", systemImage: "person.2")
                    }
                    // On the control, not on its label: the element a UI
                    // test can tap is the button.
                    .accessibilityIdentifier("site-crew")

                    // A sheet rather than a push: the diary is read here and
                    // written on the day screen underneath.
                    Button {
                        readingDiary = site
                    } label: {
                        Label("Site diary", systemImage: "text.book.closed")
                    }
                    .disabled(site == nil)
                    .accessibilityIdentifier("site-diary-list")

                    // Open on a read-only site too: an archived site's months
                    // are still the director's to ask for.
                    Button {
                        exportingMonth = nil
                        exporting = site
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(site == nil)
                    .accessibilityIdentifier("site-export")

                    Button {
                        editing = site
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .disabled(site == nil)
                    .accessibilityIdentifier("site-edit")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("site-more")
            }
        }
        .sheet(item: $exporting) { site in
            // Last month: the director asks at the start of the next one.
            SiteExportScreen(
                site: site,
                month: exportingMonth
                    ?? CalendarDate.today(in: settingsStore.workCalendar).yearMonth.adding(months: -1)
            )
        }
        // `initial`, and keyed on the site arriving, because the query may
        // not have it yet the first time the screen is drawn.
        .onChange(of: site?.id, initial: true) { _, _ in
            openLinkedExport()
        }
        .sheet(item: $readingDiary) { site in
            SiteDiaryListSheet(site: site)
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

    private func openLinkedExport() {
        guard let exportMonth, !openedLinkedExport, let site else { return }
        openedLinkedExport = true
        exportingMonth = exportMonth
        exporting = site
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
