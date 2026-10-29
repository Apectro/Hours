import SwiftUI
import SwiftData

/// One site: its name and address, four buttons for what it has — Crew,
/// Diary, Sheet, Extra work — and its month and day screen under them, with
/// the gear for the site's settings (1.2, mockup SiteHome). Nothing is
/// reachable only from a menu: crew sign-off is on the crew screen and on
/// the sheet's export screen.
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
    /// See `SiteRoute.opensExtraWorkReport`.
    var opensExtraWorkReport = false

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.openSiteCrew) private var openSiteCrew
    // Not private: the memberwise initializer the Sites tab calls would
    // become private with it.
    @Environment(\.modelContext) var modelContext

    // Every site rather than this one: whether this one is read-only depends
    // on the others (see `SiteAccess.isReadOnly`).
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var editing: Site?
    @State private var exporting: Site?
    @State private var readingDiary: Site?
    /// The buttons' counts, read on appearing and when a sheet closes.
    @State private var counts = SiteCounts()
    /// A date picked in the diary list, for the day screen to show.
    @State private var requestedDate: CalendarDate?
    /// The extra-work report, from the Extra work button.
    @State private var reporting: Site?
    /// The month the export opens on; `nil` is the Sheet button's month.
    @State private var exportingMonth: YearMonth?
    /// The link's export is opened once. Coming back to the site from the
    /// sheet must not open it again.
    @State private var openedLinkedExport = false
    /// The same, for the extra-work report a reminder links to.
    @State private var openedLinkedReport = false

    var body: some View {
        Group {
            if let site {
                SiteDayScreen(
                    site: site,
                    isReadOnly: subscriptions.isReadOnly(site, among: sites),
                    date: initialDate ?? CalendarDate.today(in: settingsStore.workCalendar),
                    appliesSameAsLastDay: appliesSameAsLastDay,
                    requestedDate: $requestedDate,
                    onOpenReport: { reporting = site },
                    header: AnyView(actions(for: site))
                )
            } else {
                Color.hoursCanvas
            }
        }
        .navigationTitle(site?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // The site's settings (the editor: name, address, job, usual
            // day, extras, arrival reminder, archiving). Everything else the
            // site has is a button on the screen itself (`SiteActionsRow`).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = site
                } label: {
                    Image(systemName: "gearshape")
                }
                .disabled(site == nil)
                .accessibilityLabel(String(localized: "Site settings"))
                .accessibilityIdentifier("site-edit")
            }
        }
        .onAppear(perform: loadCounts)
        .onChange(of: editing) { _, now in if now == nil { loadCounts() } }
        .onChange(of: reporting) { _, now in if now == nil { loadCounts() } }
        .onChange(of: readingDiary) { _, now in if now == nil { loadCounts() } }
        .sheet(item: $exporting) { site in
            // The Sheet button's month, or the one a link asked for.
            SiteExportScreen(site: site, month: exportingMonth ?? sheetMonth)
        }
        // `initial`, and keyed on the site arriving, because the query may
        // not have it yet the first time the screen is drawn.
        .onChange(of: site?.id, initial: true) { _, _ in
            openLinkedExport()
            openLinkedReport()
        }
        .sheet(item: $readingDiary) { site in
            SiteDiaryListSheet(site: site) { requestedDate = $0 }
        }
        .sheet(item: $reporting) { site in
            ExtraWorkReportScreen(site: site, canEdit: !subscriptions.isReadOnly(site, among: sites))
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

    private func openLinkedReport() {
        guard opensExtraWorkReport, !openedLinkedReport, let site else { return }
        openedLinkedReport = true
        reporting = site
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

    // MARK: - The buttons

    /// The month the Sheet button opens: last month during the first ten
    /// days, when the boss asks for it, this month after (`SignOff.defaultMonth`).
    private var sheetMonth: YearMonth {
        SignOff.defaultMonth(today: CalendarDate.today(in: settingsStore.workCalendar))
    }

    private func actions(for site: Site) -> some View {
        let setup = settingsStore.settings.siteSetup(for: site.id)
        return SiteActionsRow(
            address: site.address,
            crewCount: counts.crew + 1,
            diaryCount: setup.keepsDiary || counts.diary > 0 ? counts.diary : nil,
            sheetMonth: settingsStore.dateFormatting.monthName(sheetMonth),
            openExtraWork: counts.openExtraWork,
            onCrew: { openSiteCrew(SiteCrewRoute(siteID: site.id)) },
            onDiary: { readingDiary = site },
            onSheet: {
                exportingMonth = nil
                exporting = site
            },
            onExtraWork: { reporting = site }
        )
    }

    /// Read outside of `body`: the repositories' reads collapse duplicates,
    /// which writes.
    private func loadCounts() {
        let calendar = settingsStore.workCalendar
        let month = CalendarDate.today(in: calendar).yearMonth.range(in: calendar)
        let repository = SiteRepository(context: modelContext)
        counts = SiteCounts(
            crew: repository.crew(for: siteID, includeHidden: false).count,
            diary: SiteDiaryRepository(context: modelContext).datesWithEntries(siteID: siteID, in: month).count,
            openExtraWork: ExtraWorkRepository(context: modelContext)
                .jobs(siteID: siteID)
                .filter { !$0.isDone || $0.awaitsReport }
                .count
        )
    }
}

/// What the site's buttons count.
private struct SiteCounts: Equatable {
    /// The crew offered for a new day, not counting you.
    var crew = 0
    /// Days this month with a diary.
    var diary = 0
    /// Extra-work jobs still in progress or not sent to the boss yet.
    var openExtraWork = 0
}
