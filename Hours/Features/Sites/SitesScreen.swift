import SwiftUI
import SwiftData

/// The Sites tab: one card per active site, with this month's figures.
///
/// A card answers what a supervisor wants at a glance before opening the
/// site (1.2, mockup Sites): how many of this month's days are not written,
/// who is on it, whether today is written and what the crew has worked, and
/// a strip of the month's work days in the colour rule. Archived sites sit
/// behind one row underneath, because they are history rather than
/// somewhere work is happening, and a list that keeps growing with finished
/// jobs buries the one that is not.
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
        .environment(\.openSiteDay, OpenSiteDayAction { path.append($0) })
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
            // Today's day over the site's page, so Back leads to the site.
            next.append(SiteRoute(siteID: id))
            next.append(SiteRoute(
                siteID: id,
                date: CalendarDate.today(in: settingsStore.workCalendar),
                appliesSameAsLastDay: true
            ))
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
    /// One day on the site (1.2): the site's page pushes this from its
    /// month and its "Write today". Without it, the site's page.
    var date: CalendarDate? = nil
    /// Set by the site widget's "Same as yesterday", with today's `date`:
    /// fill today from the last written day on arrival, where the screen's
    /// own button could.
    var appliesSameAsLastDay = false
    /// Set by the monthly reminder: open the site's sheet for this month on
    /// arrival, over the site, so closing it leaves you on the site.
    var exportMonth: YearMonth? = nil
    /// Set by the weekly "extra work not sent" reminder: open the site's
    /// extra-work report on arrival, over the site, as the export above.
    var opensExtraWorkReport = false
}

/// Pushes a day of a site (a `SiteRoute` with a date) onto the Sites stack:
/// the site page's diary list picks a date from a sheet, where a
/// `NavigationLink` cannot be. Does nothing outside that stack, where the
/// site page is never shown (the calendar opens a site on its day).
struct OpenSiteDayAction {
    let open: (SiteRoute) -> Void

    func callAsFunction(_ route: SiteRoute) {
        open(route)
    }
}

private struct OpenSiteDayKey: EnvironmentKey {
    static let defaultValue = OpenSiteDayAction { _ in }
}

extension EnvironmentValues {
    var openSiteDay: OpenSiteDayAction {
        get { self[OpenSiteDayKey.self] }
        set { self[OpenSiteDayKey.self] = newValue }
    }
}

/// The archived sites, behind the last row of the Sites list.
struct ArchivedSitesRoute: Hashable {}

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

    init(month: YearMonth, calendar: Calendar) {
        self.month = month
        let range = month.range(in: calendar)
        self.range = range
        // From the look-back before the 1st: whether a day is expected
        // reads the weekdays worked lately (`SiteWorkDays`).
        let lower = range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar).key
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
                        summary: loaded.summaries[site.id] ?? SiteCardSummary(),
                        isReadOnly: isReadOnly,
                        offersSameAsLastDay: !isReadOnly && loaded.canCopyLastDay.contains(site.id)
                    )
                    .tourTarget(site.id == activeSites.first?.id ? .sites : nil)
                }

                if !archivedSites.isEmpty {
                    archivedRow
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
                        .font(.subheadline.weight(.bold))
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
                initialDate: route.date,
                appliesSameAsLastDay: route.appliesSameAsLastDay,
                exportMonth: route.exportMonth,
                opensExtraWorkReport: route.opensExtraWorkReport,
                showsSiteActions: route.date == nil
            )
        }
        .navigationDestination(for: SiteCrewRoute.self) { route in
            CrewScreen(siteID: route.siteID)
        }
        .navigationDestination(for: ArchivedSitesRoute.self) { _ in
            ArchivedSitesScreen(sites: archivedSites)
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

    /// "Archived sites 4 ›": one row, to a list of their own.
    private var archivedRow: some View {
        NavigationLink(value: ArchivedSitesRoute()) {
            HStack(spacing: Metrics.medium) {
                Text("Archived sites")
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Text(verbatim: "\(archivedSites.count)")
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.large)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sites-archived")
        .padding(.top, Metrics.small)
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
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let repository = SiteRepository(context: modelContext, lock: settings.monthLock)
        let sites = repository.sites(includeArchived: true)
        let today = CalendarDate.today(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let days = Dictionary(grouping: repository.siteDays(siteID: nil, in: lookBack), by: \.siteID)
        let holidays = SiteMonthStatuses.holidays(
            context: modelContext,
            settings: settings,
            calendar: calendar,
            range: lookBack
        )
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        // Where the card's "Same as last day" would do what the site's own
        // button does: today open to changes, nothing written for it yet,
        // and an earlier day to copy.
        let todayIsOpen = !settings.monthLock.isLocked(today)

        var summaries: [UUID: SiteCardSummary] = [:]
        var canCopy = Set<UUID>()
        for site in sites where !site.isArchived {
            let siteDays = days[site.id] ?? []
            let visible = repository.crew(for: site.id, includeHidden: false).map(\.id)
            let statuses = SiteMonthStatuses.statuses(
                siteID: site.id,
                month: month,
                siteDays: siteDays,
                visibleCrew: visible,
                settings: settings,
                calendar: calendar,
                today: today,
                holidays: holidays
            )
            let inMonth = siteDays.filter { range.contains($0.date) }
            let writtenToday = siteDays.contains { $0.date == today }
            let expectedToday = SiteWorkDays.expects(
                site.id, on: today, setup: settings.siteSetup(for: site.id),
                siteDays: siteDays, calendar: calendar, holidays: holidays
            )
            let lastDay = inMonth.isEmpty ? repository.lastSiteDay(siteID: site.id, before: today)?.date : nil
            summaries[site.id] = SiteCardSummary(
                people: visible.count + 1,
                headline: SiteMonthOverview.headline(statuses),
                strip: SiteMonthOverview.strip(statuses),
                today: writtenToday ? .written : (expectedToday ? .notWritten : .noWork),
                monthMinutes: inMonth.reduce(0) { $0 + calculator.compute($1).crewTotalMinutes },
                lastDay: lastDay
            )
            if todayIsOpen, !writtenToday, repository.lastSiteDay(siteID: site.id, before: today) != nil {
                canCopy.insert(site.id)
            }
        }
        loaded = LoadedSites(sites: sites, summaries: summaries, canCopyLastDay: canCopy)
    }
}

private struct ChangeToken: Equatable {
    var month: YearMonth
    var stamps: [Date]
}

/// What the cards are drawn from: every site, archived ones too, and each
/// active site's month in brief.
private struct LoadedSites {
    var sites: [Site] = []
    var summaries: [UUID: SiteCardSummary] = [:]
    /// Active sites whose today can be filled from their last day.
    var canCopyLastDay: Set<UUID> = []
}

/// One active site's month, as its card says it.
private struct SiteCardSummary {
    enum Today { case written, notWritten, noWork }

    /// The crew offered for a new day, you included. People hidden from the
    /// crew are left out: they are no longer on it.
    var people = 1
    var headline = SiteMonthOverview.Headline.nothingThisMonth
    var strip: [SiteMonthOverview.StripDay] = []
    var today = Today.noWork
    /// The crew's hours this month, everyone together.
    var monthMinutes = 0
    /// The last day written, for a site with nothing this month.
    var lastDay: CalendarDate?
}

/// A site's month by status, for its card and its page: the one place that
/// gathers what `SiteDayStatus` needs from the store and the settings.
@MainActor
enum SiteMonthStatuses {
    /// Date keys of public holidays off in `range`, or none when holidays
    /// are not tracked.
    static func holidays(
        context: ModelContext,
        settings: AppSettings,
        calendar: Calendar,
        range: CalendarDateRange
    ) -> Set<Int> {
        guard settings.features.trackHolidays else { return [] }
        let rules = (try? context.fetch(FetchDescriptor<HolidayRecord>()))?.map(\.rule) ?? []
        return HolidayResolver(rules: rules, calendar: calendar, covering: range).daysOffKeys(in: range, calendar: calendar)
    }

    /// Every day of `month` with its status. `siteDays` are the site's days
    /// of the month and the look-back before it (`SiteWorkDays.lookBackDays`).
    static func statuses(
        siteID: UUID,
        month: YearMonth,
        siteDays: [SiteDay],
        visibleCrew: [UUID],
        settings: AppSettings,
        calendar: Calendar,
        today: CalendarDate,
        holidays: Set<Int>
    ) -> [CalendarDate: SiteDayStatus] {
        let crew = SiteMonthOverview.crew(
            siteID: siteID,
            visible: visibleCrew,
            siteDays: siteDays,
            month: month,
            calendar: calendar
        )
        return SiteDayStatus.month(
            month,
            siteID: siteID,
            siteDays: siteDays,
            setup: settings.siteSetup(for: siteID),
            crew: crew,
            today: today,
            calendar: calendar,
            holidays: holidays
        )
    }
}

/// One active site (1.2, mockup Sites): its name and how the month stands on
/// the right — "2 not written" in red, "All written" in green, "Nothing this
/// month" in grey — then "5 people · today written · 303h this month", and a
/// strip of the month's work days in the colour rule.
///
/// The card opens the site. While today is still to be written and there is
/// a day to copy, it also offers "Same as last day" — the site's own button,
/// by the same route the site widget uses — so the commonest day on a site
/// is one tap from the list.
private struct SiteCard: View {
    let site: Site
    let summary: SiteCardSummary
    let isReadOnly: Bool
    let offersSameAsLastDay: Bool

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            NavigationLink(value: SiteRoute(siteID: site.id)) {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("site-card")

            if offersSameAsLastDay {
                sameAsLastDayLink
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Metrics.small + 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                    name
                    Spacer(minLength: Metrics.small)
                    headline
                }
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    name
                    headline
                }
            }

            Text(verbatim: detailLine)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("site-card-today")

            if !summary.strip.isEmpty, summary.headline != .nothingThisMonth {
                strip
            }

            if isReadOnly {
                Label {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(site.name)
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
    }

    private var headline: some View {
        Group {
            switch summary.headline {
            case let .notWritten(count):
                Text(String(localized: "\(count) not written", comment: "Site card: how many of this month's work days are not written"))
                    .foregroundStyle(Color.hoursMissing)
            case .allWritten:
                Text("All written")
                    .foregroundStyle(Color.hoursDone)
            case .nothingThisMonth:
                Text("Nothing this month")
                    .foregroundStyle(.hoursSecondaryText)
            }
        }
        .font(.footnote.weight(.bold))
        .accessibilityIdentifier("site-card-status")
    }

    /// "5 people · today written · 303h this month", or "3 people · last day
    /// 14 Sep" for a site with nothing this month.
    private var detailLine: String {
        var parts = [String(inflected: "^[\(summary.people) person](inflect: true)")]
        if summary.headline == .nothingThisMonth {
            if let lastDay = summary.lastDay {
                let date = settingsStore.dateFormatting.shortDate(lastDay)
                parts.append(String(localized: "last day \(date)", comment: "Site card: the last day written, for a site with nothing this month"))
            }
            return parts.joined(separator: " · ")
        }
        switch summary.today {
        case .written: parts.append(String(localized: "today written"))
        case .notWritten: parts.append(String(localized: "today not written"))
        case .noWork: break
        }
        let hours = settingsStore.settings.displayFormatting.string(summary.monthMinutes)
        parts.append(String(localized: "\(hours) this month", comment: "Site card: the crew's hours this month"))
        return parts.joined(separator: " · ")
    }

    /// The month's work days, one thin bar each. The status on the right
    /// says it in words, so VoiceOver skips the bars.
    private var strip: some View {
        HStack(spacing: 2) {
            ForEach(summary.strip, id: \.date.key) { day in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(day.status.fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var sameAsLastDayLink: some View {
        NavigationLink(
            value: SiteRoute(
                siteID: site.id,
                date: CalendarDate.today(in: settingsStore.workCalendar),
                appliesSameAsLastDay: true
            )
        ) {
            Label("Same as last day", systemImage: "arrow.uturn.backward.circle")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("site-card-same-as-last")
    }
}

/// The archived sites, each opening as any site does: everything recorded
/// on them is still there.
private struct ArchivedSitesScreen: View {
    let sites: [Site]

    var body: some View {
        List {
            Section {
                ForEach(sites) { site in
                    NavigationLink(value: SiteRoute(siteID: site.id)) {
                        Text(site.name)
                    }
                    .accessibilityIdentifier("sites-archived-site")
                }
            } footer: {
                Text("An archived site keeps every recorded day and its whole crew, and stops appearing among your active sites.")
            }
        }
        .navigationTitle("Archived sites")
        .navigationBarTitleDisplayMode(.inline)
    }
}
