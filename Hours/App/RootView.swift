import SwiftUI

/// Three tabs, calendar first.
///
/// The calendar is where the work happens, so it is the landing surface and
/// keeps its own navigation stack. Insights and Settings are destinations you
/// visit, not places you live.
struct RootView: View {
    var storeFailure: String? = nil

    @State private var selection: Destination = .calendar

    enum Destination: Hashable {
        case calendar
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
        .task {
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
            await HoursStack.subscriptions.refresh()
            await refreshReminder()
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
                // Anything that arrived from another device while the app was
                // away is merged by now, so this is the moment to notice two
                // rows meaning the same Tuesday. A no-op without sync.
                HoursStack.repository.reconcileDuplicates()
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
        let days = PeriodEngine(settings: settings, calendar: calendar).days(
            in: window,
            records: repository.records(in: window),
            holidays: repository.holidayRules()
        )
        let gaps = GapFinder.unrecordedWorkingDays(in: days, asOf: today)
        let body = GapFinder.message(for: gaps, formatting: settingsStore.dateFormatting)

        await scheduler.schedule(preferences: settings.reminders, body: body)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Destination.calendar)

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
