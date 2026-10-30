import SwiftUI
import SwiftData

/// One site, everything on one page (1.2, mockup Sites): its name as the
/// title, "address · 5 people · usually 07:00–16:00" under it, the month
/// coloured by `SiteDayStatus` with how many days are not written, then a
/// group with the Crew, A usual day, Diary, Sign-off and Extra work, and the
/// two big buttons at the bottom: Write today and the Sheet. The site's
/// settings are the Settings button top right. A day in the month opens that
/// day on the site; nothing about a site hides in a menu.
///
/// Given a date — the calendar's and the day editor's "Open on site", or a
/// day this page pushed — it shows that day instead (`SiteDayScreen`), with
/// the site's buttons above it when it was not reached from this page.
struct SiteDetailScreen: View {
    let siteID: UUID
    var initialDate: CalendarDate? = nil
    /// See `SiteRoute.appliesSameAsLastDay`.
    var appliesSameAsLastDay = false
    /// See `SiteRoute.exportMonth`.
    var exportMonth: YearMonth? = nil
    /// See `SiteRoute.opensExtraWorkReport`.
    var opensExtraWorkReport = false
    /// On a day: the site's Crew, Diary, Sheet and Extra work buttons above
    /// it (`SiteActionsRow`). Off for a day this page pushed, which has them.
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
                        onOpenReport: { reporting = site },
                        header: showsSiteActions ? AnyView(actions(for: site)) : nil
                    )
                } else {
                    overview(site)
                }
            } else {
                Color.hoursCanvas
            }
        }
        .navigationTitle(site?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // The site's settings (the editor: name, address, job, usual
            // day, extras, arrival reminder, archiving).
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = site
                } label: {
                    if showsDay {
                        Image(systemName: "gearshape")
                    } else {
                        Text("Settings")
                    }
                }
                .disabled(site == nil)
                .accessibilityLabel(String(localized: "Site settings"))
                .accessibilityIdentifier("site-edit")
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

    // MARK: - The site's page

    private func overview(_ site: Site) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.large) {
                Text(verbatim: subtitle(for: site))
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    // What the UI tests wait for: on screen whenever the
                    // page is, and never a container of buttons.
                    .accessibilityIdentifier("screen-site")

                monthSection(site)

                links(for: site)
            }
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.large)
        }
        .background(Color.hoursCanvas)
        .safeAreaInset(edge: .bottom) {
            bottomButtons(for: site)
        }
    }

    /// "Ilica 207C · 5 people · usually 07:00–16:00".
    private func subtitle(for site: Site) -> String {
        var parts: [String] = []
        if !site.address.isEmpty {
            parts.append(SiteAddress.singleLine(site.address))
        }
        parts.append(String(inflected: "^[\(counts.crew + 1) person](inflect: true)"))
        if let times = usualTimes(for: site) {
            parts.append(String(localized: "usually \(times)", comment: "A site's page: its usual times, e.g. 07:00–16:00"))
        }
        return parts.joined(separator: " · ")
    }

    /// "07:00–16:00", or nil without usual times.
    private func usualTimes(for site: Site) -> String? {
        let setup = settingsStore.settings.siteSetup(for: site.id)
        guard let start = setup.start, let end = setup.end else { return nil }
        let formatting = settingsStore.dateFormatting
        return "\(formatting.time(start, on: today))–\(formatting.time(end, on: today))"
    }

    private func monthSection(_ site: Site) -> some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(spacing: Metrics.tiny) {
                Button {
                    shownMonth = month.adding(months: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(String(localized: "Previous month"))
                .accessibilityIdentifier("site-overview-month-previous")

                Text(verbatim: settingsStore.dateFormatting.monthTitle(month))
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    shownMonth = month.adding(months: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(month >= today.yearMonth)
                .accessibilityLabel(String(localized: "Next month"))
                .accessibilityIdentifier("site-overview-month-next")

                Spacer(minLength: Metrics.small)

                if counts.missing > 0 {
                    Text(String(inflected: "^[\(counts.missing) day](inflect: true) not written"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.hoursMissing)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("site-overview-missing")
                }
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: Metrics.medium) {
                SiteStatusMonthGrid(
                    month: month,
                    statuses: counts.statuses,
                    today: today,
                    calendar: settingsStore.workCalendar,
                    formatting: settingsStore.dateFormatting,
                    route: { SiteRoute(siteID: site.id, date: $0) }
                )
                SiteStatusLegend()
            }
            .padding(Metrics.medium)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
    }

    /// Crew ›, A usual day ›, Diary ›, Sign-off ›, Extra work ›, each with
    /// its value on the right.
    private func links(for site: Site) -> some View {
        let setup = settingsStore.settings.siteSetup(for: site.id)
        let showsDiary = setup.keepsDiary || counts.diary > 0
        return VStack(spacing: 0) {
            linkRow("Crew", value: counts.crewNames, identifier: "site-crew") {
                openSiteCrew(SiteCrewRoute(siteID: site.id))
            }
            Divider().padding(.leading, Metrics.large)
            linkRow("A usual day", value: usualDayText(setup), identifier: "site-usual-day") {
                editing = site
            }
            if showsDiary {
                Divider().padding(.leading, Metrics.large)
                linkRow("Diary", value: diaryText, identifier: "site-diary-list") {
                    readingDiary = site
                }
            }
            Divider().padding(.leading, Metrics.large)
            linkRow("Sign-off", value: signOffText, identifier: "site-overview-sign-off") {
                signingOff = site
            }
            Divider().padding(.leading, Metrics.large)
            linkRow("Extra work", value: extraWorkText, identifier: "site-extra-work-report") {
                reporting = site
            }
        }
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.large)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .contentShape(Rectangle())
        }
        // A Button reads its texts as one label: "Crew, Marijo, Ivan +2".
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// "07:00–16:00 · Mon–Fri".
    private func usualDayText(_ setup: SiteSetup) -> String {
        let text = SiteSetupText(
            formatting: settingsStore.dateFormatting,
            durations: settingsStore.settings.displayFormatting,
            calendar: settingsStore.workCalendar
        )
        let times = site.flatMap(usualTimes(for:)) ?? String(localized: "Not set")
        return "\(times) · \(text.workDays(setup.workDays))"
    }

    private var diaryText: String {
        counts.diary == 0
            ? String(localized: "None this month")
            : String(inflected: "^[\(counts.diary) day](inflect: true)")
    }

    private var signOffText: String {
        switch counts.signOff {
        case .notYet:
            return String(localized: "Not yet")
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

    /// Write today, and the Sheet: side by side, one above the other at the
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
            .buttonStyle(.bigAction(.primary, isMain: true))
            .accessibilityIdentifier("site-write-today")

            Button {
                exportingMonth = nil
                exporting = site
            } label: {
                Text("Sheet")
            }
            .buttonStyle(.bigAction(.secondary, isMain: true))
            .accessibilityIdentifier("site-export")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.top, Metrics.small)
        .padding(.bottom, Metrics.small)
        .background(Color.hoursCanvas)
    }

    // MARK: - On a day

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

        // You first, then the crew in their order: "Marijo, Ivan, Marko +2".
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = [owner.isEmpty ? String(localized: "You") : owner] + crew.map(\.name)
        loaded.crewNames = names.count > 3
            ? names.prefix(3).joined(separator: ", ") + " +\(names.count - 3)"
            : names.joined(separator: ", ")

        // The shown month with the look-back its first days are judged by.
        let range = month.range(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let days = repository.siteDays(siteID: siteID, in: lookBack)
        loaded.statuses = SiteMonthStatuses.statuses(
            siteID: siteID,
            month: month,
            siteDays: days,
            visibleCrew: crew.map(\.id),
            settings: settings,
            calendar: calendar,
            today: today,
            holidays: SiteMonthStatuses.holidays(context: modelContext, settings: settings, calendar: calendar, range: lookBack)
        )
        loaded.missing = SiteDayStatus.missingCount(in: loaded.statuses)
        loaded.writtenToday = repository.siteDay(siteID: siteID, on: today) != nil

        // The sign-off of the month the Sheet opens on.
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
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
private struct SiteCounts: Equatable {
    /// The crew offered for a new day, not counting you.
    var crew = 0
    /// Days this month with a diary.
    var diary = 0
    /// Extra-work jobs still in progress or not sent to the boss yet.
    var openExtraWork = 0
    /// "Marijo, Ivan, Marko +2".
    var crewNames = ""
    /// The shown month, day by day.
    var statuses: [CalendarDate: SiteDayStatus] = [:]
    var missing = 0
    var writtenToday = false
    var signOff = SiteMonthOverview.SignOffProgress.notYet
}
