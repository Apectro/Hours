import SwiftUI
import SwiftData

/// The Sites tab: one card per active site, with this month's figures.
///
/// A card answers what a supervisor wants at a glance before opening the
/// site — who is on it, how many days have been written up this month and
/// what the crew has worked between them. Archived sites sit folded away
/// underneath, because they are history rather than somewhere work is
/// happening, and a list that keeps growing with finished jobs buries the
/// one that is not.
struct SitesScreen: View {
    /// A link from a widget or a notification, handed down by the root and
    /// cleared once followed, so the same link arriving again is followed
    /// again.
    @Binding var link: AppLink?

    @Environment(SettingsStore.self) private var settingsStore

    /// A path of values, so the site screen's menu can push the crew by value
    /// (see `OpenSiteCrewAction`).
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SitesContent(
                month: CalendarDate.today(in: settingsStore.workCalendar).yearMonth,
                calendar: settingsStore.workCalendar
            )
        }
        // On the stack rather than its root view, so the screens pushed onto
        // it are handed the action too.
        .environment(\.openSiteCrew, OpenSiteCrewAction { path.append($0) })
        // `initial`, because the tab may be built by the very link that
        // selected it.
        .onChange(of: link, initial: true) { _, newLink in
            follow(newLink)
        }
    }

    /// Opens what a widget asked for by replacing the path with it: by value,
    /// as every other screen on this stack is pushed, and from the list, so
    /// Back leads where it always does.
    private func follow(_ newLink: AppLink?) {
        guard let newLink else { return }
        var next = NavigationPath()
        switch newLink {
        // Today's editor is the calendar's; the root never sends it here.
        case .sites, .writeToday:
            break
        case let .site(id):
            next.append(SiteRoute(siteID: id))
        case let .siteSameAsLastDay(id):
            next.append(SiteRoute(siteID: id, appliesSameAsLastDay: true))
        case let .siteExport(id, month):
            next.append(SiteRoute(siteID: id, exportMonth: month))
        case let .siteExtraWork(id):
            next.append(SiteRoute(siteID: id, opensExtraWorkReport: true))
        }
        path = next
        link = nil
    }
}

/// Where a site card leads. Its own type rather than a bare `UUID`, so that
/// another screen pushing a `UUID` for some other purpose cannot land here.
struct SiteRoute: Hashable {
    let siteID: UUID
    /// Set by the site widget's "Same as yesterday": fill today from the last
    /// written day on arrival, where the screen's own button could.
    var appliesSameAsLastDay = false
    /// Set by the monthly reminder: open the site's sheet for this month on
    /// arrival, over the site, so closing it leaves you on the site.
    var exportMonth: YearMonth? = nil
    /// Set by the weekly "extra work not sent" reminder: open the site's
    /// extra-work report on arrival, over the site, as the export above.
    var opensExtraWorkReport = false
}

/// A site's crew list, pushed from the site screen. A value like `SiteRoute`,
/// so every destination in the stack is pushed by value: a presented-binding
/// destination on the site screen, mixed with these, left the app never
/// going idle once the crew was opened.
struct SiteCrewRoute: Hashable {
    let siteID: UUID
}

/// Pushes a site's crew onto the navigation stack the site screen is in.
///
/// The site screen keeps Crew in its toolbar menu, and a `NavigationLink`
/// does not work from inside a `Menu`. A presented binding is not an option
/// either: mixed with the value routes, it left the app never going idle. So
/// each stack that shows a site — the Sites tab and the day editor's "Open on
/// site" — owns a path, and hands down this action to append to it.
struct OpenSiteCrewAction {
    let open: (SiteCrewRoute) -> Void

    func callAsFunction(_ route: SiteCrewRoute) {
        open(route)
    }
}

private struct OpenSiteCrewKey: EnvironmentKey {
    // Does nothing outside a stack that provides it, which only a preview is.
    static let defaultValue = OpenSiteCrewAction { _ in }
}

extension EnvironmentValues {
    var openSiteCrew: OpenSiteCrewAction {
        get { self[OpenSiteCrewKey.self] }
        set { self[OpenSiteCrewKey.self] = newValue }
    }
}

/// The list itself, in its own view so the month can go into its `@Query`, as
/// `PeriodDataProvider` does for days.
private struct SitesContent: View {
    let month: YearMonth
    private let range: CalendarDateRange

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext

    // Watched rather than read. The figures come from `SiteRepository`, which
    // owns the duplicate rules; these exist so SwiftData says when anything
    // under the cards changed — here, on another screen, or by sync.
    @Query private var siteEntries: [SiteEntry]
    @Query private var crewEntries: [CrewMemberEntry]
    @Query private var dayEntries: [SiteDayEntry]

    @State private var loaded = LoadedSites()
    @State private var isCreating = false
    @State private var paywallReason: ProFeature?
    @State private var showsArchived = false

    init(month: YearMonth, calendar: Calendar) {
        self.month = month
        let range = month.range(in: calendar)
        self.range = range
        let lower = range.start.key
        let upper = range.end.key
        _siteEntries = Query(sort: \SiteEntry.sortOrder)
        _crewEntries = Query(sort: \CrewMemberEntry.sortOrder)
        _dayEntries = Query(
            filter: #Predicate<SiteDayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sort: \SiteDayEntry.dateKey
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.medium) {
                if activeSites.isEmpty {
                    emptyState
                }

                ForEach(activeSites) { site in
                    let isReadOnly = subscriptions.isReadOnly(site, among: loaded.sites)
                    SiteCard(
                        site: site,
                        coworkers: loaded.crewCounts[site.id] ?? 0,
                        days: loaded.days[site.id] ?? [],
                        isReadOnly: isReadOnly,
                        offersSameAsLastDay: !isReadOnly && loaded.canCopyLastDay.contains(site.id)
                    )
                    .tourTarget(site.id == activeSites.first?.id ? .sites : nil)
                }

                if !archivedSites.isEmpty {
                    archivedSection
                }
            }
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.extraLarge)
        }
        .background(Color.hoursCanvas)
        .navigationTitle("Sites")
        // A screen the UI tests wait for. The title beside it is translated.
        .accessibilityIdentifier("screen-sites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addSite) {
                    Image(systemName: "plus")
                        .proLock(needsProForAnotherSite)
                }
                .accessibilityLabel("Add a site")
                .accessibilityIdentifier("sites-add")
            }
        }
        .navigationDestination(for: SiteRoute.self) { route in
            SiteDetailScreen(
                siteID: route.siteID,
                appliesSameAsLastDay: route.appliesSameAsLastDay,
                exportMonth: route.exportMonth,
                opensExtraWorkReport: route.opensExtraWorkReport
            )
        }
        .navigationDestination(for: SiteCrewRoute.self) { route in
            CrewScreen(siteID: route.siteID)
        }
        .sheet(isPresented: $isCreating) {
            SiteEditorSheet(
                site: Site(name: "", sortOrder: nextSortOrder),
                isNew: true
            )
        }
        .paywall(for: $paywallReason)
        .onChange(of: changeToken, initial: true) { _, _ in
            reload()
        }
    }

    // MARK: - Parts

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No sites yet", systemImage: "building.2")
        } description: {
            Text("Add the site you work on, then its crew. Each day the times are entered once, for everyone who was there.")
        } actions: {
            Button("Add a site", action: addSite)
                .buttonStyle(.borderedProminent)
        }
        .tourTarget(.sites)
        .padding(.top, Metrics.extraLarge)
    }

    private var archivedSection: some View {
        DisclosureGroup(isExpanded: $showsArchived) {
            VStack(spacing: Metrics.small) {
                ForEach(archivedSites) { site in
                    NavigationLink(value: SiteRoute(siteID: site.id)) {
                        HStack(spacing: Metrics.medium) {
                            Text(site.name)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(Metrics.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color.hoursSurface,
                            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, Metrics.small)
        } label: {
            Text("Archived")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, Metrics.medium)
    }

    // MARK: - Data

    private var activeSites: [Site] { loaded.sites.filter { !$0.isArchived } }
    private var archivedSites: [Site] { loaded.sites.filter(\.isArchived) }

    /// After every site there is, archived ones included, so a new site never
    /// takes the place of the one that stays free if Pro lapses — that is the
    /// active site with the lowest sort order (see `SiteAccess`).
    private var nextSortOrder: Int {
        (loaded.sites.map(\.sortOrder).max() ?? -1) + 1
    }

    /// The first site is free; a second active one is Pro.
    private var needsProForAnotherSite: Bool {
        !subscriptions.canAddSite(activeSites: activeSites.count)
    }

    private func addSite() {
        if needsProForAnotherSite {
            paywallReason = .multipleSites
        } else {
            isCreating = true
        }
    }

    /// Changes whenever a row under the cards does, or the month turns.
    private var changeToken: ChangeToken {
        ChangeToken(
            month: month,
            stamps: siteEntries.map(\.updatedAt) + crewEntries.map(\.updatedAt) + dayEntries.map(\.updatedAt)
        )
    }

    /// Read through the repository outside of `body`: its reads collapse
    /// duplicates, which writes, and a view must not write while it is being
    /// drawn.
    private func reload() {
        let repository = SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock)
        let sites = repository.sites(includeArchived: true)
        var counts: [UUID: Int] = [:]
        for site in sites {
            counts[site.id] = repository.crew(for: site.id, includeHidden: false).count
        }
        let days = Dictionary(grouping: repository.siteDays(siteID: nil, in: range), by: \.siteID)
        // Where the card's "Same as last day" would do what the site's own
        // button does: today open to changes, nothing written for it yet,
        // and an earlier day to copy.
        let today = CalendarDate.today(in: settingsStore.workCalendar)
        var canCopy = Set<UUID>()
        if !settingsStore.settings.monthLock.isLocked(today) {
            for site in sites where !site.isArchived {
                let writtenToday = days[site.id]?.contains { $0.date == today } ?? false
                if !writtenToday, repository.lastSiteDay(siteID: site.id, before: today) != nil {
                    canCopy.insert(site.id)
                }
            }
        }
        loaded = LoadedSites(sites: sites, crewCounts: counts, days: days, canCopyLastDay: canCopy)
    }
}

private struct ChangeToken: Equatable {
    var month: YearMonth
    var stamps: [Date]
}

/// What the cards are drawn from: every site, archived ones too, how many
/// people other than you are on each crew, and this month's days by site.
private struct LoadedSites {
    var sites: [Site] = []
    var crewCounts: [UUID: Int] = [:]
    var days: [UUID: [SiteDay]] = [:]
    /// Active sites whose today can be filled from their last day.
    var canCopyLastDay: Set<UUID> = []
}

/// One active site, as screen 1 of the mockup draws it, with a line saying
/// whether today has been written up on it.
///
/// The upper part opens the site. While today is still to be written and
/// there is a day to copy, the card also offers "Same as last day" — the
/// site's own button, by the same route the site widget uses — and "Open",
/// so the commonest day on a site is one tap from the list.
private struct SiteCard: View {
    let site: Site
    /// The crew offered for a new day, not counting you. People hidden from
    /// the crew are left out: they are no longer on it.
    let coworkers: Int
    let days: [SiteDay]
    let isReadOnly: Bool
    let offersSameAsLastDay: Bool

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                NavigationLink(value: SiteRoute(siteID: site.id)) {
                    summary
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("site-card")

                if offersSameAsLastDay {
                    actions
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(site.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text(crewLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            todayLine

            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(
                    label: String(localized: "Days this month"),
                    value: "\(days.count)"
                )
                Divider().frame(maxHeight: .infinity)
                StatTile(
                    label: String(localized: "Crew hours"),
                    value: settingsStore.settings.displayFormatting.string(crewMinutes)
                )
            }
            // The divider as tall as the taller tile, at any text size.
            .fixedSize(horizontal: false, vertical: true)

            if isReadOnly {
                Label {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Links by value, like the card itself, so they push onto the Sites
    /// stack. Side by side while they fit, one above the other otherwise.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.small) {
                sameAsLastDayLink
                openLink
            }
            VStack(spacing: Metrics.small) {
                sameAsLastDayLink
                openLink
            }
        }
    }

    private var sameAsLastDayLink: some View {
        NavigationLink(value: SiteRoute(siteID: site.id, appliesSameAsLastDay: true)) {
            Label("Same as last day", systemImage: "arrow.uturn.backward.circle")
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("site-card-same-as-last")
    }

    private var openLink: some View {
        NavigationLink(value: SiteRoute(siteID: site.id)) {
            Text("Open")
                .font(.body.weight(.medium))
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("site-card-open")
    }

    /// Whether today is written up yet: the one thing worth knowing before
    /// opening a site at the end of a working day.
    private var todayLine: some View {
        let isWritten = days.contains { $0.date == CalendarDate.today(in: settingsStore.workCalendar) }
        return Label {
            Text(isWritten ? String(localized: "Today: written") : String(localized: "Today: not written yet"))
                .foregroundStyle(isWritten ? Color.secondary : Color.hoursNegative)
        } icon: {
            Image(systemName: isWritten ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isWritten ? Color.accentColor : Color.hoursNegative)
        }
        .font(.subheadline)
        .accessibilityIdentifier("site-card-today")
    }

    private var crewLine: String {
        guard coworkers > 0 else { return String(localized: "Crew: just you") }
        return String(inflected: "Crew: you + ^[\(coworkers) coworker](inflect: true)")
    }

    /// Worked out the way the site day screen works it out, so the card and
    /// the days behind it can never disagree.
    private var crewMinutes: Int {
        let calculator = SiteDayCalculator(
            settings: settingsStore.settings,
            calendar: settingsStore.workCalendar
        )
        return days.reduce(0) { $0 + calculator.compute($1).crewTotalMinutes }
    }
}
