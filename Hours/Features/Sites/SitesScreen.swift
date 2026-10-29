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
                } else {
                    overview
                }

                ForEach(activeSites) { site in
                    let isReadOnly = subscriptions.isReadOnly(site, among: loaded.sites)
                    SiteCard(
                        site: site,
                        coworkers: loaded.crewCounts[site.id] ?? 0,
                        today: loaded.today[site.id],
                        isExpectedToday: loaded.expectedToday.contains(site.id),
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
            // The way to a new site, said in words (1.2): the wizard.
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addSite) {
                    Label("New site", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .proLock(needsProForAnotherSite)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
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
        .fullScreenCover(isPresented: $isCreating) {
            NewSiteWizard()
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
            Button("New site", action: addSite)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sites-empty-add")
        }
        .tourTarget(.sites)
        .padding(.top, Metrics.extraLarge)
    }

    /// "12 active · 3 need today written": how many sites, and how many are
    /// expected today with nothing written yet (said only when there are).
    private var overview: some View {
        let active = activeSites.count
        let missing = activeSites.filter { loaded.expectedToday.contains($0.id) && loaded.today[$0.id] == nil }.count
        var parts = [String(localized: "\(active) active", comment: "Sites list: how many active sites")]
        if missing > 0 {
            parts.append(String(
                localized: "\(missing) need today written",
                comment: "Sites list: how many sites are expected today and have nothing written"
            ))
        }
        return Text(verbatim: parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("sites-overview")
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
                // On the label, which is the control that opens the
                // section; never on the group, which holds the site links.
                .accessibilityIdentifier("sites-archived")
        }
        .padding(.top, Metrics.medium)
    }

    // MARK: - Data

    private var activeSites: [Site] { loaded.sites.filter { !$0.isArchived } }
    private var archivedSites: [Site] { loaded.sites.filter(\.isArchived) }

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
        // Whether each site is expected today (1.2): its work days, or the
        // weekdays it was worked lately, and never on a public holiday off.
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let recent = repository.siteDays(
            siteID: nil,
            in: CalendarDateRange(start: today.adding(days: -SiteWorkDays.lookBackDays, in: calendar), end: today)
        )
        var holidays = Set<Int>()
        if settings.features.trackHolidays {
            let rules = (try? modelContext.fetch(FetchDescriptor<HolidayRecord>()))?.map(\.rule) ?? []
            let range = CalendarDateRange(single: today)
            holidays = HolidayResolver(rules: rules, calendar: calendar, covering: range).daysOffKeys(in: range, calendar: calendar)
        }
        var expected = Set<UUID>()
        for site in sites where !site.isArchived {
            if SiteWorkDays.expects(
                site.id, on: today, setup: settings.siteSetup(for: site.id),
                siteDays: recent, calendar: calendar, holidays: holidays
            ) {
                expected.insert(site.id)
            }
        }
        var todays: [UUID: SiteDay] = [:]
        for (siteID, list) in days {
            if let day = list.first(where: { $0.date == today }) { todays[siteID] = day }
        }
        loaded = LoadedSites(
            sites: sites,
            crewCounts: counts,
            days: days,
            canCopyLastDay: canCopy,
            today: todays,
            expectedToday: expected
        )
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
    /// Each site's day today, where one is written.
    var today: [UUID: SiteDay] = [:]
    /// Active sites a day is expected on today (`SiteWorkDays.expects`).
    var expectedToday: Set<UUID> = []
}

/// One active site (1.2, mockup Main): its name and address, a line with a
/// dot saying where today stands — written, with how many were there and the
/// crew's hours; not written yet on a day it is worked; no work today — and
/// small chips for what is on: the crew, the arrival reminder, the
/// allowance.
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
    /// Today's day on the site, when it is written.
    let today: SiteDay?
    let isExpectedToday: Bool
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
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(site.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if !site.address.isEmpty {
                Text(verbatim: SiteAddress.singleLine(site.address))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if site.place == nil {
                // Sites made several at once have neither yet.
                Label("Add the place in the site's settings", systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            todayLine

            chips

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

    /// Where today stands: the one thing worth knowing before opening a
    /// site at the end of a working day.
    private var todayLine: some View {
        let state = todayState
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(verbatim: state.text)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(state.textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("site-card-today")
    }

    private var todayState: (text: String, color: Color, textColor: Color) {
        if let today {
            let calculator = SiteDayCalculator(settings: settingsStore.settings, calendar: settingsStore.workCalendar)
            let minutes = calculator.compute(today).crewTotalMinutes
            let hours = settingsStore.settings.displayFormatting.string(minutes)
            let text = String(
                localized: "Today written · \(today.present.count) of \(coworkers + 1) here · \(hours)",
                comment: "Site card; the values are how many were there, how many could have been, and the crew's hours today"
            )
            return (text, Color.hoursPositive, Color.primary)
        }
        if isExpectedToday {
            return (String(localized: "Today not written yet"), Color.hoursNegativeFill, Color.hoursNegative)
        }
        return (String(localized: "No work today"), Color.secondary, Color.secondary)
    }

    /// What is on, in small grey chips.
    private var chips: some View {
        var labels = [String(localized: "Crew \(coworkers + 1)", comment: "Site card chip; the value is how many people, you included")]
        if site.monitorsArrival {
            labels.append(String(localized: "Arrival reminder"))
        }
        if settingsStore.settings.allowance.isEnabled && site.allowanceByDefault {
            labels.append(String(localized: "Field allowance"))
        }
        // In a row while they fit; one under another at large text sizes.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.tiny + 2) {
                ForEach(labels, id: \.self, content: chip)
            }
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(labels, id: \.self, content: chip)
            }
        }
    }

    private func chip(_ label: String) -> some View {
        Text(verbatim: label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.small)
            .padding(.vertical, Metrics.tiny)
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: Metrics.chipCornerRadius, style: .continuous)
            )
    }
}
