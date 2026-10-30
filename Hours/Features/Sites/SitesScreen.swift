import SwiftUI
import SwiftData

/// The Sites tab (design v2, mockup Sites phone 1): a plain grouped list, a
/// row per active site with its name, "5 people · 462h this month" and how
/// it stands on the right — red "2 not written", orange "Today open", a
/// green tick when the month is all written — then the month's sheets, then
/// one row to the archived sites, which are history rather than somewhere
/// work is happening.
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
    // under the rows changed — here, on another screen, or by sync.
    @Query private var siteEntries: [SiteEntry]
    @Query private var crewEntries: [CrewMemberEntry]
    @Query private var dayEntries: [SiteDayEntry]

    @State private var loaded = LoadedSites()
    @State private var isCreating = false
    @State private var paywallReason: ProFeature?

    /// How many months back the list offers a sheet for, this one included.
    private static let sheetMonths = 3

    init(month: YearMonth, calendar: Calendar) {
        self.month = month
        let range = month.range(in: calendar)
        self.range = range
        // From the look-back before the 1st, as whether a day is expected
        // reads the weekdays worked lately (`SiteWorkDays`), or from the
        // oldest month offered a sheet if that is earlier.
        let lookBack = range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar)
        let oldestSheet = month.adding(months: -(Self.sheetMonths - 1)).firstDay
        let lower = min(lookBack, oldestSheet).key
        let upper = range.end.key
        _siteEntries = Query(sort: \SiteEntry.sortOrder)
        _crewEntries = Query(sort: \CrewMemberEntry.sortOrder)
        _dayEntries = Query(
            filter: #Predicate<SiteDayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sort: \SiteDayEntry.dateKey
        )
    }

    var body: some View {
        List {
            if activeSites.isEmpty {
                Section {
                    emptyState
                }
            } else {
                Section {
                    ForEach(activeSites) { site in
                        let isReadOnly = subscriptions.isReadOnly(site, among: loaded.sites)
                        SiteRow(
                            site: site,
                            summary: loaded.summaries[site.id] ?? SiteCardSummary(),
                            isReadOnly: isReadOnly,
                            offersSameAsLastDay: !isReadOnly && loaded.canCopyLastDay.contains(site.id)
                        )
                        .tourTarget(site.id == activeSites.first?.id ? .sites : nil)
                    }
                } footer: {
                    if activeSites.contains(where: { subscriptions.isReadOnly($0, among: loaded.sites) }) {
                        Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                    }
                }
            }

            if !loaded.monthSheets.isEmpty {
                Section {
                    ForEach(loaded.monthSheets) { sheet in
                        MonthSheetRow(sheet: sheet)
                    }
                } header: {
                    Text("Sheets")
                }
            }

            if !archivedSites.isEmpty {
                Section {
                    archivedRow
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sites")
        // A screen the UI tests wait for. The title beside it is translated.
        .accessibilityIdentifier("screen-sites")
        .toolbar {
            // The new-site wizard, under the same Pro rule as before.
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addSite) {
                    Image(systemName: "plus")
                        .proLock(needsProForAnotherSite)
                }
                .accessibilityLabel(String(localized: "New site"))
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
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("sites-empty-add")
        }
        .tourTarget(.sites)
    }

    /// "Archived  4 ›": one row, to a list of their own.
    private var archivedRow: some View {
        NavigationLink(value: ArchivedSitesRoute()) {
            HStack(spacing: Metrics.small) {
                Text("Archived")
                Spacer(minLength: Metrics.small)
                Text(verbatim: "\(archivedSites.count)")
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
            }
        }
        .accessibilityIdentifier("sites-archived")
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

    /// Changes whenever a row under the list does, or the month turns.
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
        let allDays = repository.siteDays(siteID: nil, in: lookBack)
        let days = Dictionary(grouping: allDays, by: \.siteID)
        // Every crew, hidden people too: the same person on two sites is
        // matched by name when a day is checked for who was missing.
        let members = sites.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        let holidays = SiteMonthStatuses.holidays(
            context: modelContext,
            settings: settings,
            calendar: calendar,
            range: lookBack
        )
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        // Where the row's "Same as last day" would do what the site's own
        // button does: today open to changes, nothing written for it yet,
        // and an earlier day to copy.
        let todayIsOpen = !settings.monthLock.isLocked(today)

        var summaries: [UUID: SiteCardSummary] = [:]
        var canCopy = Set<UUID>()
        for site in sites where !site.isArchived {
            let siteDays = days[site.id] ?? []
            let visible = members.filter { $0.siteID == site.id && !$0.isHidden }
            let statuses = SiteMonthStatuses.statuses(
                siteID: site.id,
                month: month,
                siteDays: allDays,
                members: members,
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
                today: writtenToday ? .written : (expectedToday ? .notWritten : .noWork),
                monthMinutes: inMonth.reduce(0) { $0 + calculator.compute($1).crewTotalMinutes },
                lastDay: lastDay
            )
            if todayIsOpen, !writtenToday, repository.lastSiteDay(siteID: site.id, before: today) != nil {
                canCopy.insert(site.id)
            }
        }
        loaded = LoadedSites(
            sites: sites,
            summaries: summaries,
            canCopyLastDay: canCopy,
            monthSheets: monthSheets(sites: sites, repository: repository, calculator: calculator, today: today)
        )
    }

    /// The months offered a sheet, each with the sites worked on it in the
    /// list's order and the crew's hours on all of them.
    private func monthSheets(
        sites: [Site],
        repository: SiteRepository,
        calculator: SiteDayCalculator,
        today: CalendarDate
    ) -> [MonthSheet] {
        let oldest = month.adding(months: -(Self.sheetMonths - 1))
        let span = CalendarDateRange(start: oldest.firstDay, end: range.end)
        var worked: [YearMonth: [UUID: Int]] = [:]
        var seen = Set<String>()
        for day in repository.siteDays(siteID: nil, in: span) {
            // Sync can deliver a site day twice; the first one counts.
            guard seen.insert("\(day.siteID.uuidString)-\(day.date.key)").inserted else { continue }
            worked[YearMonth(day.date), default: [:]][day.siteID, default: 0] += calculator.compute(day).crewTotalMinutes
        }
        let names = Dictionary(sites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return CrewSheetSites.months(worked: Set(worked.keys), today: today, limit: Self.sheetMonths).map { month in
            let hours = worked[month] ?? [:]
            let ids = CrewSheetSites.ticked(worked: hours, order: sites.map(\.id), opened: nil)
            return MonthSheet(
                month: month,
                siteNames: ids.compactMap { names[$0] },
                minutes: hours.values.reduce(0, +)
            )
        }
    }
}

private struct ChangeToken: Equatable {
    var month: YearMonth
    var stamps: [Date]
}

/// What the list is drawn from: every site, archived ones too, and each
/// active site's month in brief.
private struct LoadedSites {
    var sites: [Site] = []
    var summaries: [UUID: SiteCardSummary] = [:]
    /// Active sites whose today can be filled from their last day.
    var canCopyLastDay: Set<UUID> = []
    /// The months offered a sheet, newest first.
    var monthSheets: [MonthSheet] = []
}

/// One month's sheet of every site worked on it: "October" over "Trg Pravde
/// + Jarunski · 782h". The export is presented from the row itself, not from
/// the list's root, so it never competes with a sheet a pushed site day
/// presents.
private struct MonthSheetRow: View {
    let sheet: MonthSheet

    @Environment(SettingsStore.self) private var settingsStore
    @State private var isExporting = false

    var body: some View {
        Button {
            isExporting = true
        } label: {
            HStack(spacing: Metrics.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: settingsStore.dateFormatting.monthTitle(sheet.month))
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.small)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sites-month-sheet")
        .sheet(isPresented: $isExporting) {
            ExportScreen(
                initialRange: sheet.month.range(in: settingsStore.workCalendar),
                month: sheet.month,
                crewSheet: true
            )
        }
    }

    private var detail: String {
        let hours = settingsStore.settings.displayFormatting.string(sheet.minutes)
        return sheet.siteNames.joined(separator: " + ") + " · " + hours
    }
}

/// A month's sheet of every site worked on it, as the Sites list offers it.
private struct MonthSheet: Identifiable {
    var month: YearMonth
    var siteNames: [String]
    var minutes: Int

    var id: YearMonth { month }
}

/// One active site's month, as its row says it.
private struct SiteCardSummary {
    enum Today { case written, notWritten, noWork }

    /// The crew offered for a new day, you included. People hidden from the
    /// crew are left out: they are no longer on it.
    var people = 1
    var headline = SiteMonthOverview.Headline.nothingThisMonth
    var today = Today.noWork
    /// The crew's hours this month, everyone together.
    var monthMinutes = 0
    /// The last day written, for a site with nothing this month.
    var lastDay: CalendarDate?
}

/// A site's month by status, for its row and its page: the one place that
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

    /// Every day of `month` with its status.
    ///
    /// - `siteDays`: every site's days of the month and the look-back before
    ///   it (`SiteWorkDays.lookBackDays`): a day here is not partly for
    ///   someone another site had that day.
    /// - `members`: every site's crew, hidden people too, to match the same
    ///   person across sites by name (`SiteMonthOverview.crew`).
    static func statuses(
        siteID: UUID,
        month: YearMonth,
        siteDays: [SiteDay],
        members: [CrewMember],
        settings: AppSettings,
        calendar: Calendar,
        today: CalendarDate,
        holidays: Set<Int>
    ) -> [CalendarDate: SiteDayStatus] {
        let check = SiteMonthOverview.crew(
            siteID: siteID,
            members: members,
            siteDays: siteDays,
            month: month,
            calendar: calendar
        )
        return SiteDayStatus.month(
            month,
            siteID: siteID,
            siteDays: siteDays,
            setup: settings.siteSetup(for: siteID),
            check: check,
            today: today,
            calendar: calendar,
            holidays: holidays
        )
    }
}

/// One active site (design v2, mockup Sites phone 1): its name, under it
/// "5 people · 462h this month" (or "Last day 14 Sep"), and on the right how
/// it stands, the most important first — red "2 not written", orange "Today
/// open", a green tick when the month is all written — then the chevron.
///
/// The row opens the site. While today is still to be written and there is
/// a day to copy, a swipe and a long press also offer "Same as last day", by
/// the same route the site widget uses.
private struct SiteRow: View {
    let site: Site
    let summary: SiteCardSummary
    let isReadOnly: Bool
    let offersSameAsLastDay: Bool

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openSiteDay) private var openSiteDay

    var body: some View {
        NavigationLink(value: SiteRoute(siteID: site.id)) {
            HStack(spacing: Metrics.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: site.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: detailLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("site-card-today")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                status
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("site-card")
        .swipeActions(edge: .leading) {
            if offersSameAsLastDay {
                Button(action: sameAsLastDay) {
                    Label("Same as last day", systemImage: "arrow.uturn.backward")
                }
                .tint(.accentColor)
                .accessibilityIdentifier("site-card-same-as-last")
            }
        }
        .contextMenu {
            if offersSameAsLastDay {
                Button(action: sameAsLastDay) {
                    Label("Same as last day", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    /// The most important thing about the site right now, or nothing.
    @ViewBuilder
    private var status: some View {
        Group {
            if isReadOnly {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityLabel(String(localized: "Read-only"))
            } else if case let .notWritten(count) = summary.headline {
                Text(String(localized: "\(count) not written", comment: "Site card: how many of this month's work days are not written"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursMissing)
            } else if summary.today == .notWritten {
                Text("Today open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursAttention)
            } else if summary.headline == .allWritten {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.hoursDone)
                    .accessibilityLabel(String(localized: "All written"))
            }
        }
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier("site-card-status")
    }

    /// "5 people · 462h this month", or "Last day 14 Sep" for a site with
    /// nothing this month.
    private var detailLine: String {
        if summary.headline == .nothingThisMonth, summary.monthMinutes == 0, let lastDay = summary.lastDay {
            let date = settingsStore.dateFormatting.shortDate(lastDay)
            return String(localized: "Last day \(date)", comment: "Sites list: the last day written, for a site with nothing this month")
        }
        let people = String(inflected: "^[\(summary.people) person](inflect: true)")
        guard summary.monthMinutes > 0 else { return people }
        let hours = settingsStore.settings.displayFormatting.string(summary.monthMinutes)
        return people + " · " + String(localized: "\(hours) this month", comment: "Site card: the crew's hours this month")
    }

    /// Today's day over the site's page, so Back leads to the site.
    private func sameAsLastDay() {
        let today = CalendarDate.today(in: settingsStore.workCalendar)
        openSiteDay(SiteRoute(siteID: site.id))
        openSiteDay(SiteRoute(siteID: site.id, date: today, appliesSameAsLastDay: true))
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
                        Text(verbatim: site.name)
                    }
                    .accessibilityIdentifier("sites-archived-site")
                }
            } footer: {
                Text("An archived site keeps every recorded day and its whole crew, and stops appearing among your active sites.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Archived sites")
        .navigationBarTitleDisplayMode(.inline)
    }
}
