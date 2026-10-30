import SwiftUI
import SwiftData

/// One site (design v2, mockup Sites phone 2): its name as the large title,
/// "address · 5 people · 7:00 – 15:00" under it, the month with how many
/// days are not written and a dot under each day, then the rows Crew, A
/// usual day, Diary, Sign-off and Extra work, the month's figures, and the
/// two buttons at the bottom: Write today and the Sheet. The `ellipsis`
/// menu holds the site's settings and every other site action. A day in the
/// month opens that day on the site.
///
/// Given a date — the calendar's and the day editor's "Open on site", or a
/// day this page pushed — it shows that day instead (`SiteDayScreen`); a day
/// not reached from this page keeps the site's actions in its own menu.
struct SiteDetailScreen: View {
    let siteID: UUID
    var initialDate: CalendarDate? = nil
    /// See `SiteRoute.appliesSameAsLastDay`.
    var appliesSameAsLastDay = false
    /// See `SiteRoute.exportMonth`.
    var exportMonth: YearMonth? = nil
    /// See `SiteRoute.opensExtraWorkReport`.
    var opensExtraWorkReport = false
    /// On a day: the site's actions (crew, diary, sheet, extra work,
    /// settings) in the day's menu. Off for a day this page pushed: Back is
    /// the way to them.
    var showsSiteActions = true

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.openSiteCrew) private var openSiteCrew
    @Environment(\.openSiteDay) private var openSiteDay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Not private: the memberwise initializer the Sites tab calls would
    // become private with it.
    @Environment(\.modelContext) var modelContext

    // Every site rather than this one: whether this one is read-only depends
    // on the others (see `SiteAccess.isReadOnly`).
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var editing: Site?
    @State private var exporting: Site?
    @State private var readingDiary: Site?
    @State private var signingOff: Site?
    /// What the page shows, read on appearing and when a sheet closes.
    @State private var counts = SiteCounts()
    /// A date picked in the diary list, for the day screen to show.
    @State private var requestedDate: CalendarDate?
    /// The extra-work report, from the Extra work row.
    @State private var reporting: Site?
    /// The month the export opens on; `nil` is the Sheet button's month.
    @State private var exportingMonth: YearMonth?
    /// The link's export is opened once. Coming back to the site from the
    /// sheet must not open it again.
    @State private var openedLinkedExport = false
    /// The same, for the extra-work report a reminder links to.
    @State private var openedLinkedReport = false
    /// The month the page shows; `nil` is this month.
    @State private var shownMonth: YearMonth?

    /// A day rather than the site's page.
    private var showsDay: Bool { initialDate != nil || appliesSameAsLastDay }

    var body: some View {
        Group {
            if let site {
                if showsDay {
                    SiteDayScreen(
                        site: site,
                        isReadOnly: subscriptions.isReadOnly(site, among: sites),
                        date: initialDate ?? today,
                        appliesSameAsLastDay: appliesSameAsLastDay,
                        requestedDate: $requestedDate,
                        onOpenReport: { reporting = site }
                    )
                    .toolbar {
                        if showsSiteActions {
                            ToolbarItem(placement: .topBarTrailing) {
                                siteMenu(site)
                            }
                        }
                    }
                } else {
                    overview(site)
                }
            } else {
                Color.hoursCanvas
            }
        }
        .onAppear(perform: load)
        .onChange(of: editing) { _, now in if now == nil { load() } }
        .onChange(of: reporting) { _, now in if now == nil { load() } }
        .onChange(of: readingDiary) { _, now in if now == nil { load() } }
        .onChange(of: signingOff) { _, now in if now == nil { load() } }
        .onChange(of: shownMonth) { _, _ in load() }
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
        .onChange(of: requestedDate) { _, date in
            // On the site's page, a date picked in the diary opens that day.
            guard !showsDay, let date else { return }
            requestedDate = nil
            openSiteDay(SiteRoute(siteID: siteID, date: date))
        }
        .sheet(item: $readingDiary) { site in
            SiteDiaryListSheet(site: site) { requestedDate = $0 }
        }
        .sheet(item: $reporting) { site in
            ExtraWorkReportScreen(site: site, canEdit: !subscriptions.isReadOnly(site, among: sites))
        }
        .sheet(item: $signingOff) { site in
            SiteSignOffSheet(site: site)
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

    private var today: CalendarDate {
        CalendarDate.today(in: settingsStore.workCalendar)
    }

    private var month: YearMonth {
        shownMonth ?? today.yearMonth
    }

    /// The month the Sheet button opens: last month during the first ten
    /// days, when the boss asks for it, this month after (`SignOff.defaultMonth`).
    private var sheetMonth: YearMonth {
        SignOff.defaultMonth(today: today)
    }

    // MARK: - The menu

    /// The site's settings and every other site action, in one `ellipsis`
    /// menu. Each is also a row or a button on the page; on a day reached
    /// from the calendar this menu is the way to them.
    private func siteMenu(_ site: Site) -> some View {
        Menu {
            Button {
                editing = site
            } label: {
                Label("Site settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("site-edit")

            Button {
                openSiteCrew(SiteCrewRoute(siteID: site.id))
            } label: {
                Label("Crew", systemImage: "person.2")
            }
            .accessibilityIdentifier("site-menu-crew")

            if showsDiary(for: site) {
                Button {
                    readingDiary = site
                } label: {
                    Label("Diary", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("site-menu-diary")
            }

            Button {
                signingOff = site
            } label: {
                Label("Crew sign-off", systemImage: "signature")
            }
            .accessibilityIdentifier("site-menu-sign-off")

            Button {
                exportingMonth = nil
                exporting = site
            } label: {
                Label("Sheet", systemImage: "doc.richtext")
            }
            .accessibilityIdentifier("site-menu-sheet")

            Button {
                reporting = site
            } label: {
                Label("Extra work", systemImage: "hammer")
            }
            .accessibilityIdentifier("site-menu-extra-work")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(String(localized: "More"))
        .accessibilityIdentifier("site-menu")
    }

    // MARK: - The site's page

    private func overview(_ site: Site) -> some View {
        List {
            Section {
                Text(verbatim: subtitle(for: site))
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    // What the UI tests wait for: on screen whenever the
                    // page is, and never a container of buttons.
                    .accessibilityIdentifier("screen-site")
                    .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + 4, bottom: Metrics.small, trailing: Metrics.large))
                    .listRowBackground(Color.clear)

                monthHeader
                    .listRowInsets(EdgeInsets(top: Metrics.medium, leading: Metrics.large + 4, bottom: Metrics.small, trailing: Metrics.small))
                    .listRowBackground(Color.clear)

                // The month sits on the background, not in a card.
                SiteMonthCalendar(
                    month: month,
                    statuses: counts.statuses,
                    today: today,
                    calendar: settingsStore.workCalendar,
                    formatting: settingsStore.dateFormatting,
                    onSelect: { openSiteDay(SiteRoute(siteID: site.id, date: $0)) }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.small, bottom: 0, trailing: Metrics.small))
                .listRowBackground(Color.clear)
            }
            .listRowSeparator(.hidden)

            Section {
                rows(for: site)
            }

            if counts.figures != nil {
                Section {
                    figures
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle(Text(verbatim: site.name))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                siteMenu(site)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomButtons(for: site)
        }
    }

    /// "Ilica 207C · 5 people · 7:00 – 15:00".
    private func subtitle(for site: Site) -> String {
        var parts: [String] = []
        if !site.address.isEmpty {
            parts.append(SiteAddress.singleLine(site.address))
        }
        parts.append(String(inflected: "^[\(counts.crew + 1) person](inflect: true)"))
        if let times = usualTimes(for: site) {
            parts.append(times)
        }
        return parts.joined(separator: " · ")
    }

    /// "7:00 – 15:00", or nil without usual times.
    private func usualTimes(for site: Site) -> String? {
        let setup = settingsStore.settings.siteSetup(for: site.id)
        guard let start = setup.start, let end = setup.end else { return nil }
        return SiteDayStyle.range(start, end, on: today, formatting: settingsStore.dateFormatting)
    }

    /// "October ‹ ›" on the left, "2 days not written" in red on the right.
    private var monthHeader: some View {
        HStack(spacing: Metrics.tiny) {
            Text(verbatim: settingsStore.dateFormatting.monthName(month))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(settingsStore.dateFormatting.monthTitle(month))

            Button {
                shownMonth = month.adding(months: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(String(localized: "Previous month"))
            .accessibilityIdentifier("site-overview-month-previous")

            Button {
                shownMonth = month.adding(months: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(month >= today.yearMonth)
            .accessibilityLabel(String(localized: "Next month"))
            .accessibilityIdentifier("site-overview-month-next")

            Spacer(minLength: Metrics.small)

            if counts.missing > 0 {
                Text(String(inflected: "^[\(counts.missing) day](inflect: true) not written"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursMissing)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("site-overview-missing")
            }
        }
        .buttonStyle(.borderless)
    }

    /// Crew ›, A usual day ›, Diary ›, Sign-off ›, Extra work ›, each with
    /// its value in grey on the right.
    @ViewBuilder
    private func rows(for site: Site) -> some View {
        let setup = settingsStore.settings.siteSetup(for: site.id)
        linkRow("Crew", value: "\(counts.crew + 1)", identifier: "site-crew") {
            openSiteCrew(SiteCrewRoute(siteID: site.id))
        }
        linkRow("A usual day", value: usualDayText(setup), identifier: "site-usual-day") {
            editing = site
        }
        if showsDiary(for: site) {
            linkRow("Diary", value: diaryText, identifier: "site-diary-list") {
                readingDiary = site
            }
        }
        linkRow("Sign-off", value: signOffText, identifier: "site-overview-sign-off") {
            signingOff = site
        }
        linkRow("Extra work", value: extraWorkText, identifier: "site-extra-work-report") {
            reporting = site
        }
    }

    private func showsDiary(for site: Site) -> Bool {
        settingsStore.settings.siteSetup(for: site.id).keepsDiary || counts.diary > 0
    }

    private func linkRow(
        _ title: LocalizedStringKey,
        value: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.small) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Text(verbatim: value)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        // A Button reads its texts as one label: "Crew, 5".
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityIdentifier(identifier)
    }

    /// The shown month's figures: days written, the crew's hours, yours,
    /// and the days the weather stopped work when there were any.
    @ViewBuilder
    private var figures: some View {
        if let figures = counts.figures {
            let durations = settingsStore.settings.displayFormatting
            valueRow("Days written", value: "\(figures.daysWritten)")
            valueRow("Crew hours", value: durations.string(figures.crewMinutes))
            valueRow("You", value: durations.string(figures.yourMinutes))
            if figures.badWeatherDays > 0 {
                valueRow("Bad weather", value: "\(figures.badWeatherDays)")
                    .accessibilityIdentifier("site-month-bad-weather")
            }
        }
    }

    private func valueRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: Metrics.small) {
            Text(title)
            Spacer(minLength: Metrics.small)
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// "7:00 – 15:00 · Mon–Fri".
    private func usualDayText(_ setup: SiteSetup) -> String {
        let text = SiteSetupText(
            formatting: settingsStore.dateFormatting,
            durations: settingsStore.settings.displayFormatting,
            calendar: settingsStore.workCalendar
        )
        guard let times = site.flatMap(usualTimes(for:)) else { return String(localized: "Not set") }
        return dynamicTypeSize.isAccessibilitySize ? times : "\(times) · \(text.workDays(setup.workDays))"
    }

    private var diaryText: String {
        counts.diary == 0
            ? String(localized: "None this month")
            : String(inflected: "^[\(counts.diary) day](inflect: true)")
    }

    private var signOffText: String {
        switch counts.signOff {
        case .notYet:
            return String(localized: "Not signed")
        case let .partial(signed, total):
            return String(localized: "\(signed) of \(total) signed", comment: "A site's Sign-off row: how many of the crew signed the month")
        case .all:
            return String(localized: "All signed")
        }
    }

    private var extraWorkText: String {
        counts.openExtraWork == 0
            ? String(localized: "None open")
            : String(localized: "\(counts.openExtraWork) open", comment: "Site button: how many extra-work jobs are not finished or not sent yet")
    }

    /// Write today and the Sheet, side by side; one above the other at the
    /// largest text sizes.
    private func bottomButtons(for site: Site) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            NavigationLink(value: SiteRoute(siteID: site.id, date: today)) {
                if counts.writtenToday {
                    Text("Today")
                } else {
                    Text("Write today")
                }
            }
            .buttonStyle(.bigAction(.primary))
            .layoutPriority(1)
            .accessibilityIdentifier("site-write-today")

            Button {
                exportingMonth = nil
                exporting = site
            } label: {
                Text("Sheet")
            }
            .buttonStyle(.bigAction(.secondary))
            .accessibilityIdentifier("site-export")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.top, Metrics.small)
        .padding(.bottom, Metrics.small)
        .background(Color.hoursCanvas)
    }

    // MARK: - Loading

    /// Read outside of `body`: the repositories' reads collapse duplicates,
    /// which writes.
    private func load() {
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let thisMonth = today.yearMonth.range(in: calendar)
        let repository = SiteRepository(context: modelContext)
        let crew = repository.crew(for: siteID, includeHidden: false)
        var loaded = SiteCounts(
            crew: crew.count,
            diary: SiteDiaryRepository(context: modelContext).datesWithEntries(siteID: siteID, in: thisMonth).count,
            openExtraWork: ExtraWorkRepository(context: modelContext)
                .jobs(siteID: siteID)
                .filter { !$0.isDone || $0.awaitsReport }
                .count
        )
        guard !showsDay else {
            counts = loaded
            return
        }

        // The shown month with the look-back its first days are judged by,
        // on every site: someone another site had that day is not missing.
        let range = month.range(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let allDays = repository.siteDays(siteID: nil, in: lookBack)
        let members = repository.sites(includeArchived: true).flatMap { repository.crew(for: $0.id, includeHidden: true) }
        loaded.statuses = SiteMonthStatuses.statuses(
            siteID: siteID,
            month: month,
            siteDays: allDays,
            members: members,
            settings: settings,
            calendar: calendar,
            today: today,
            holidays: SiteMonthStatuses.holidays(context: modelContext, settings: settings, calendar: calendar, range: lookBack)
        )
        loaded.missing = SiteDayStatus.missingCount(in: loaded.statuses)
        loaded.writtenToday = repository.siteDay(siteID: siteID, on: today) != nil

        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        loaded.figures = SiteMonthFigures(
            days: allDays.filter { $0.siteID == siteID },
            month: month,
            calculator: calculator
        )

        // The sign-off of the month the Sheet opens on.
        let signOffResults = repository.siteDays(siteID: siteID, in: sheetMonth.range(in: calendar)).map { calculator.compute($0) }
        loaded.signOff = SiteMonthOverview.signOff(
            siteID: siteID,
            month: sheetMonth,
            results: signOffResults,
            signatures: SiteDiaryRepository(context: modelContext).signatures(siteID: siteID, month: sheetMonth)
        )
        counts = loaded
    }
}

/// What the site's page shows beyond the site itself.
private struct SiteCounts {
    /// The crew offered for a new day, not counting you.
    var crew = 0
    /// Days this month with a diary.
    var diary = 0
    /// Extra-work jobs still in progress or not sent to the boss yet.
    var openExtraWork = 0
    /// The shown month, day by day.
    var statuses: [CalendarDate: SiteDayStatus] = [:]
    var missing = 0
    var writtenToday = false
    var signOff = SiteMonthOverview.SignOffProgress.notYet
    /// The shown month's days written, hours and bad-weather days.
    var figures: SiteMonthFigures?
}
