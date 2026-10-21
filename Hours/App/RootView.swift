import SwiftUI
import SwiftData

/// Four tabs, calendar first.
///
/// The calendar is where the work happens, so it is the landing surface and
/// keeps its own navigation stack. Sites sits beside it because a supervisor
/// writes up the crew's day there as often as their own. Insights and
/// Settings are destinations you visit, not places you live.
struct RootView: View {
    var storeFailure: String? = nil

    @State private var selection: Destination = .calendar
    /// A widget's or a notification's link, waiting for the Sites tab to
    /// follow it.
    @State private var siteLink: AppLink?
    /// The first-run setup, shown once on a fresh install.
    @State private var showsSetup = false
    /// Where the setup's last screen asked to go, followed once it has gone.
    @State private var setupFinish: FirstRunFinish?
    @State private var afterSetup: FirstRunFinish?

    enum Destination: Hashable {
        case calendar
        case sites
        case insights
        case settings
    }

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            // Above the tabs rather than floating over them: a warning that
            // covers the navigation bar is worse than the problem it reports.
            if let storeFailure {
                StoreFailureBanner(message: storeFailure)
            }
            tabs
        }
        // A widget's buttons are links, because a widget cannot write the
        // store (see `AppLink`). Anything that is not one of ours is ignored
        // and the app opens where it was.
        .onOpenURL { url in
            guard let link = AppLink(url: url) else { return }
            follow(link)
        }
        // A tapped notification's link, followed the same way. `initial`,
        // because a tap that launched the app arrives before this view does.
        .onChange(of: HoursStack.notificationLinks.pending, initial: true) { _, link in
            guard let link else { return }
            HoursStack.notificationLinks.pending = nil
            follow(link)
        }
        .fullScreenCover(isPresented: $showsSetup, onDismiss: setupDismissed) {
            FirstRunSetupView { finish in
                setupFinish = finish
                showsSetup = false
            }
        }
        // From the root rather than from a tab, so neither tab needs to know
        // the setup exists. One sheet, chosen by value.
        .sheet(item: $afterSetup) { finish in
            switch finish {
            case .writeToday:
                DayEditorSheet(date: CalendarDate.today(in: settingsStore.workCalendar))
            case .createSite:
                SiteEditorSheet(site: Site(name: ""), isNew: true)
            }
        }
        .task {
            // Before anything below writes to the store, which would make a
            // fresh install look like an existing one.
            decideFirstRun()
            // Only ever true behind a launch argument the UI test target
            // passes, and it writes into the in-memory store those tests use,
            // so it cannot reach anyone's real hours.
            if SampleData.isRequested {
                SampleData.seed(
                    into: HoursStack.repository,
                    calendar: HoursStack.calendar,
                    today: CalendarDate.today(in: HoursStack.calendar)
                )
            }
            if SampleData.isSiteRequested {
                SampleData.seedSite(
                    into: SiteRepository(context: HoursStack.container.mainContext),
                    calendar: HoursStack.calendar,
                    today: CalendarDate.today(in: HoursStack.calendar)
                )
            }
            if SampleData.isClosedMonthRequested {
                let month = CalendarDate.today(in: HoursStack.calendar).yearMonth
                settingsStore.update { $0.monthLock.lock(month) }
            }
            await HoursStack.subscriptions.detectInstallSource()
            await HoursStack.subscriptions.refresh()
            await refreshReminder()
            await refreshMonthlySheets()
            HoursStack.refreshWidget()
        }
        .onChange(of: scenePhase) { _, phase in
            // Rewritten on every return to the app, so the body names the days
            // that are actually missing rather than going stale.
            if phase == .active {
                // A subscription can lapse, be refunded, or be bought on
                // another device while this one sleeps.
                Task { await HoursStack.subscriptions.refresh() }
                Task { await refreshReminder() }
                Task { await refreshSiteReminders() }
                Task { await refreshMonthlySheets() }
                // Anything that arrived from another device while the app was
                // away is merged by now, so this is the moment to notice two
                // rows meaning the same Tuesday. A no-op without sync.
                HoursStack.repository.reconcileDuplicates()
                SiteRepository(context: HoursStack.container.mainContext).reconcileDuplicates()
                HoursStack.refreshWidget()
            }
            // And again on the way out, which is the moment the widget is about
            // to be looked at. Individual edits refresh as they happen; this
            // catches everything else — a changed setting, a deleted holiday —
            // without every screen in the app having to remember to.
            if phase == .background {
                HoursStack.refreshWidget()
            }
        }
    }

    /// Shows the setup on a fresh install, and remembers that anyone else
    /// has no need of it (see `FirstRunSetup`).
    private func decideFirstRun() {
        if FirstRunPreference.isForced {
            showsSetup = true
            return
        }
        // The UI tests start from exactly what a fresh install looks like.
        // They are not shown it, and they do not write the flag on the
        // machine running them.
        guard !HoursStack.isRunningUITests else { return }

        switch FirstRunSetup.decide(
            isDone: FirstRunPreference.isDone,
            hasStoredData: hasStoredData,
            settings: settingsStore.settings
        ) {
        case .show:
            showsSetup = true
        case .skip:
            FirstRunPreference.isDone = true
        case .nothing:
            break
        }
    }

    /// Any day, holiday or site at all. Sync being on counts too: it is only
    /// ever switched on by someone already using the app, and their days may
    /// not have arrived yet.
    private var hasStoredData: Bool {
        if SyncPreference.isEnabled { return true }
        let days = (try? modelContext.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        let holidays = (try? modelContext.fetchCount(FetchDescriptor<HolidayRecord>())) ?? 0
        let sites = (try? modelContext.fetchCount(FetchDescriptor<SiteEntry>())) ?? 0
        return days + holidays + sites > 0
    }

    /// Done whichever way it ended, so it is never shown again. Then on to
    /// the tab the last screen asked for, with its sheet over it.
    private func setupDismissed() {
        if !HoursStack.isRunningUITests {
            FirstRunPreference.isDone = true
        }
        guard let finish = setupFinish else { return }
        setupFinish = nil
        selection = finish == .writeToday ? .calendar : .sites
        afterSetup = finish
    }

    /// Every link the app follows is a place on the Sites tab.
    private func follow(_ link: AppLink) {
        selection = .sites
        siteLink = link
    }

    private func refreshMonthlySheets() async {
        await MonthlySheetRefresher.refresh(context: modelContext, settingsStore: settingsStore)
    }

    private func refreshSiteReminders() async {
        await SiteReminderRefresher.refresh(
            context: modelContext,
            preferences: settingsStore.settings.reminders,
            calendar: settingsStore.workCalendar
        )
    }

    private func refreshReminder() async {
        let settings = settingsStore.settings
        let scheduler = ReminderScheduler()
        guard settings.reminders.isEnabled else {
            scheduler.cancel()
            return
        }

        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        let window = GapFinder.window(
            endingAt: today,
            lookBackDays: settings.reminders.lookBackDays,
            calendar: calendar
        )
        let repository = WorkdayRepository(context: modelContext)
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate()).days(
            in: window,
            records: repository.records(in: window),
            holidays: repository.holidayRules()
        )
        let gaps = GapFinder.unrecordedWorkingDays(in: days, asOf: today)
        let body = GapMessage.text(for: gaps, formatting: settingsStore.dateFormatting)

        await scheduler.schedule(preferences: settings.reminders, body: body)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Destination.calendar)

            SitesScreen(link: $siteLink)
                .tabItem { Label("Sites", systemImage: "building.2") }
                .tag(Destination.sites)

            StatisticsScreen()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(Destination.insights)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Destination.settings)
        }
    }
}

private struct StoreFailureBanner: View {
    let message: String
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                Spacer(minLength: 0)
                Button {
                    withAnimation { isVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(Metrics.medium)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .foregroundStyle(Color.hoursNegative)
            .padding(.horizontal, Metrics.medium)
            .padding(.bottom, Metrics.small)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
