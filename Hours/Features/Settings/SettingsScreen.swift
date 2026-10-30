import SwiftUI
import SwiftData
import UIKit

/// The settings index (1.2 redesign, board 15).
///
/// What you look after most is on the first screen — Your work, Sites &
/// crews, Days & sheets — each row with what it is set to on the right, so
/// checking a setting does not need a tap. Everything else (jobs, fields,
/// calendar, look, iCloud, privacy, help) is one row further, under More.
/// The search field at the top still finds any setting by its name, what it
/// is set to, or a word it is known by ("overtime", "km", "iCloud"), the
/// screens under More and one level down included.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var isShowingPaywall = false
    @State private var isShowingFeedbackAddress = false
    /// The running balance and the leave still to book, for the two rows
    /// that show them. Worked out when the screen appears rather than on
    /// every redraw: each is a pass over the year's days.
    @State private var figures = SettingsFigures()
    /// Only More is a value route; the rows push their screens on top.
    @State private var path: [SettingsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                List {
                    if isSearching {
                        searchResults
                    } else {
                        proSection
                        ForEach(index.homeGroups) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    SettingsEntryLink(entry: entry)
                                }
                            } header: {
                                Text(verbatim: group.title)
                            }
                        }
                        Section {
                            NavigationLink(value: SettingsRoute.more) {
                                Text("More: jobs, fields, calendar, look, iCloud, privacy, help")
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("settings-more")
                        }
                    }
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search settings")
                )
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .more: SettingsMoreScreen(figures: figures)
                    }
                }
                // The tour's last stop is Sheets, on this first screen and
                // perhaps below the fold; Show the tour again is under More.
                .onChange(of: tour?.tour?.stop) { _, stop in
                    guard stop == .export else { return }
                    query = ""
                    path = []
                    withAnimation { scroller.scrollTo(SettingsIndex.exportRow, anchor: .center) }
                }
                .onAppear { figures = SettingsFigures(settingsStore: settingsStore, context: modelContext) }
                .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
                .feedbackAddressAlert(isPresented: $isShowingFeedbackAddress)
                .navigationTitle("Settings")
                // A screen the UI tests wait for. The title beside it is translated.
                .accessibilityIdentifier("screen-settings")
            }
        }
    }

    private var index: SettingsIndex {
        SettingsIndex(
            settingsStore: settingsStore,
            figures: figures,
            rate: { openURL(ReviewPrompt.writeReviewURL) },
            sendFeedback: sendFeedback
        )
    }

    @ViewBuilder
    private var searchResults: some View {
        let found = index.matches(query)
        if found.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(found) { entry in
                    SettingsEntryLink(entry: entry)
                }
            }
        }
    }

    /// Nothing is sold while the first release is free (`FreeLaunch`); the
    /// row and the tester switch return with payments.
    @ViewBuilder
    private var proSection: some View {
        if subscriptions.offersPurchases {
            Section {
                Button {
                    isShowingPaywall = true
                } label: {
                    SettingsRow(
                        // The product name does not translate; the verb
                        // in front of it does.
                        title: subscriptions.isPro
                            ? AppIdentity.proName
                            : String(localized: "Unlock Zeitkonto Pro"),
                        value: subscriptions.isPro ? String(localized: "Active") : nil,
                        systemImage: subscriptions.isPro ? "checkmark.seal" : "sparkles"
                    )
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-pro")
            } footer: {
                if !subscriptions.isPro {
                    Text("Timesheets, widgets, a second job and range editing. Recording your hours is free and stays free.")
                }
            }

            // Only in a TestFlight install, where Pro is unlocked without
            // paying (see `TesterAccess`). The switch is how a tester sees
            // the paywall and tries a purchase as a customer would.
            if subscriptions.isTestFlightInstall {
                Section {
                    Toggle("Pro unlocked for testing", isOn: Binding(
                        get: { !subscriptions.testerLocksPro },
                        set: {
                            subscriptions.setTesterLocksPro(!$0)
                            HoursStack.refreshWidget()
                        }
                    ))
                    .accessibilityIdentifier("settings-tester-pro")
                } header: {
                    Text("TestFlight")
                } footer: {
                    Text("Only in TestFlight builds. Switch it off to see the paywall and try buying as a customer would. The App Store version always asks people to pay.")
                }
            }
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func sendFeedback() {
        SettingsIndex.sendFeedback(openURL: openURL) { isShowingFeedbackAddress = true }
    }
}

/// Where the settings index goes by value.
enum SettingsRoute: Hashable {
    case more
}

/// Settings › More (1.2): the rows that are not looked at every week —
/// jobs, fields, calendar, look, iCloud, privacy, help, rating and feedback.
struct SettingsMoreScreen: View {
    let figures: SettingsFigures

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openURL) private var openURL
    @State private var isShowingFeedbackAddress = false

    var body: some View {
        let entries = index.moreEntries
        List {
            ForEach(SettingsIndex.moreSections, id: \.self) { ids in
                Section {
                    ForEach(entries.filter { ids.contains($0.id) }) { entry in
                        SettingsEntryLink(entry: entry)
                    }
                }
            }
        }
        .feedbackAddressAlert(isPresented: $isShowingFeedbackAddress)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-settings-more")
    }

    private var index: SettingsIndex {
        SettingsIndex(
            settingsStore: settingsStore,
            figures: figures,
            rate: { openURL(ReviewPrompt.writeReviewURL) },
            sendFeedback: { SettingsIndex.sendFeedback(openURL: openURL) { isShowingFeedbackAddress = true } }
        )
    }
}

private extension View {
    /// What Send feedback shows when no mail account is set up.
    func feedbackAddressAlert(isPresented: Binding<Bool>) -> some View {
        alert("Send feedback", isPresented: isPresented) {
            Button("Copy address") { UIPasteboard.general.string = ReviewPrompt.feedbackAddress }
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(
                localized: "No mail app is set up on this phone. Write to \(ReviewPrompt.feedbackAddress) from any mail app.",
                comment: "Feedback without a mail account; the value is an email address"
            ))
        }
    }
}

/// The two figures on the index that need the recorded days: the running
/// balance (Overtime & balance) and the leave still to book (Leave).
struct SettingsFigures {
    var balanceMinutes: Int?
    var leaveLeft: HalfDays?

    init() {}

    @MainActor
    init(settingsStore: SettingsStore, context: ModelContext) {
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        let repository = WorkdayRepository(context: context)
        let holidays = repository.holidayRules()
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
        if settings.features.showsBalance {
            // The same figure as the widget and Insights' running balance.
            balanceMinutes = engine.runningBalance(
                through: today,
                holidays: holidays,
                countingThrough: today,
                records: { repository.records(in: $0) }
            )
        }
        let leaveYear = settings.leave.leaveYear(containing: today, calendar: calendar)
        let range = settings.leave.range(ofLeaveYear: leaveYear, calendar: calendar)
        leaveLeft = LeaveCalculator.balance(
            leaveYear: leaveYear,
            days: engine.days(in: range, records: repository.records(in: range), holidays: holidays),
            settings: settings,
            calendar: calendar,
            today: today
        ).remaining
    }
}

/// Every setting the index knows: the rows on the first screen, the ones
/// under More, and the screens one level down that only the search finds.
@MainActor
struct SettingsIndex {
    let settingsStore: SettingsStore
    let figures: SettingsFigures
    let rate: () -> Void
    let sendFeedback: () -> Void

    static let exportRow = "settings-export-options"

    /// The rows under More, in their sections.
    static let moreSections: [[String]] = [
        ["settings-jobs", "settings-fields", "settings-calendar", "settings-theme"],
        ["settings-icloud-backup", "settings-privacy"],
        ["settings-help", "settings-rate", "settings-feedback"],
    ]

    /// Every entry whose title, value or keywords hold what was typed,
    /// case and accents aside; More and the screens one level down
    /// included.
    func matches(_ query: String) -> [SettingsEntry] {
        let needle = SettingsEntry.fold(query.trimmingCharacters(in: .whitespaces))
        var seen = Set<String>()
        return (homeGroups.flatMap(\.entries) + moreEntries + deeperEntries).filter { entry in
            seen.insert(entry.id).inserted && entry.searchText.contains(needle)
        }
    }

    /// Opens a mail to the developer; with no mail account set up nothing
    /// opens, and `noMail` shows the address instead so it can be written to.
    static func sendFeedback(openURL: OpenURLAction, noMail: @escaping () -> Void) {
        guard let url = ReviewPromptStore.feedbackMailURL else { return }
        openURL(url) { accepted in
            if !accepted { noMail() }
        }
    }

    // MARK: - The first screen

    var homeGroups: [SettingsGroup] {
        [
            SettingsGroup(id: "work", title: String(localized: "Your work"), entries: [
                SettingsEntry(
                    id: "settings-schedule",
                    title: String(localized: "Working hours"),
                    detail: scheduleSummary,
                    keywords: String(localized: "schedule, week, contract, hours, start, end, break, weekdays", comment: "Settings search words for Working hours"),
                    systemImage: "calendar.badge.clock",
                    tint: .blue,
                    kind: .page(AnyView(ScheduleSettingsScreen()))
                ),
                SettingsEntry(
                    id: "settings-calculation",
                    title: String(localized: "Overtime & balance"),
                    detail: calculationSummary,
                    keywords: String(localized: "overtime, balance, rounding, daylight saving, clock change, closed months, opening balance, carry over", comment: "Settings search words for Overtime & balance"),
                    systemImage: "plusminus",
                    tint: .orange,
                    kind: .page(AnyView(CalculationSettingsScreen()))
                ),
                SettingsEntry(
                    id: "settings-pay",
                    title: String(localized: "Pay"),
                    detail: paySummary,
                    keywords: String(localized: "pay, rate, money, wage, surcharge, night, currency, earnings, allowance, travel, km", comment: "Settings search words for Pay"),
                    systemImage: "eurosign",
                    tint: .green,
                    kind: .page(AnyView(PaySettingsScreen(jobID: settings.primaryJob.id)))
                ),
                SettingsEntry(
                    id: "settings-leave",
                    title: String(localized: "Leave"),
                    detail: leaveSummary,
                    keywords: String(localized: "leave, vacation, holiday allowance, days off, carry over", comment: "Settings search words for Leave"),
                    systemImage: "beach.umbrella",
                    tint: .teal,
                    kind: .page(AnyView(LeaveSettingsScreen()))
                ),
            ]),
            SettingsGroup(id: "sites", title: String(localized: "Sites & crews"), entries: [
                SettingsEntry(
                    id: "settings-new-sites",
                    title: String(localized: "New sites start with"),
                    detail: newSitesSummary,
                    keywords: String(localized: "site, crew, usual day, work days, new site, wizard, allowance, kilometres", comment: "Settings search words for New sites start with"),
                    systemImage: "building.2",
                    tint: .brown,
                    kind: .page(AnyView(NewSitesSettingsScreen()))
                ),
                SettingsEntry(
                    id: "settings-reminders",
                    title: String(localized: "Reminders"),
                    detail: remindersSummary,
                    keywords: String(localized: "reminders, notifications, evening, 1st of the month, extra work, gaps", comment: "Settings search words for Reminders"),
                    systemImage: "bell",
                    tint: .red,
                    kind: .page(AnyView(ReminderSettingsScreen()))
                ),
            ]),
            SettingsGroup(id: "days", title: String(localized: "Days & sheets"), entries: [
                SettingsEntry(
                    id: "settings-day-types-holidays",
                    title: String(localized: "Day types & holidays"),
                    detail: dayTypesSummary,
                    keywords: String(localized: "day types, sick, vacation, bad weather, public holidays, holidays, country", comment: "Settings search words for Day types & holidays"),
                    systemImage: "tag",
                    tint: .purple,
                    kind: .page(AnyView(DayTypesAndHolidaysScreen()))
                ),
                SettingsEntry(
                    id: Self.exportRow,
                    title: String(localized: "Sheets"),
                    detail: settings.export.language.title,
                    keywords: String(localized: "export options, export, timesheet, PDF, Excel, CSV, columns, report language, name on sheet, date format", comment: "Settings search words for Sheets"),
                    systemImage: "tablecells",
                    tint: .blue,
                    kind: .page(AnyView(ExportSettingsScreen()))
                ),
            ]),
        ]
    }

    // MARK: - Under More

    var moreEntries: [SettingsEntry] {
        [
            SettingsEntry(
                id: "settings-jobs",
                title: String(localized: "Jobs"),
                detail: jobsSummary,
                keywords: String(localized: "jobs, employer, second job", comment: "Settings search words for Jobs"),
                systemImage: "bag",
                tint: .indigo,
                kind: .page(AnyView(JobSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-fields",
                title: String(localized: "Fields"),
                detail: fieldsSummary,
                keywords: String(localized: "fields, breaks, notes, location, tags", comment: "Settings search words for Fields"),
                systemImage: "slider.horizontal.3",
                tint: .gray,
                kind: .page(AnyView(TrackingSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-calendar",
                title: String(localized: "Calendar"),
                detail: settings.calendar.showWeekends ? String(localized: "All days") : String(localized: "Weekdays only"),
                keywords: String(localized: "calendar, weekends, first day of the week, week view", comment: "Settings search words for Calendar"),
                systemImage: "square.grid.3x3",
                tint: .cyan,
                kind: .page(AnyView(CalendarSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-theme",
                title: String(localized: "Appearance"),
                detail: settings.appearance.title,
                keywords: String(localized: "appearance, theme, dark, light, bigger buttons, high contrast, gloves", comment: "Settings search words for Appearance"),
                systemImage: "circle.lefthalf.filled",
                tint: .gray,
                kind: .page(AnyView(AppearanceSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-icloud-backup",
                title: String(localized: "iCloud & backup"),
                detail: icloudSummary,
                keywords: String(localized: "iCloud, sync, backup, restore, delete everything, data, file", comment: "Settings search words for iCloud & backup"),
                systemImage: "icloud",
                tint: .blue,
                kind: .page(AnyView(ICloudAndBackupScreen()))
            ),
            SettingsEntry(
                id: "settings-privacy",
                title: String(localized: "Privacy"),
                detail: HoursStack.isSyncing
                    ? String(localized: "Your own iCloud only")
                    : String(localized: "Nothing leaves your phone"),
                keywords: String(localized: "privacy, location, data", comment: "Settings search words for Privacy"),
                systemImage: "hand.raised",
                tint: .blue,
                kind: .page(AnyView(AboutScreen()))
            ),
            SettingsEntry(
                id: "settings-help",
                title: String(localized: "Help & tour"),
                detail: String(localized: "What is where in Zeitkonto"),
                keywords: String(localized: "help, tour, guide, where", comment: "Settings search words for Help & tour"),
                systemImage: "questionmark.circle",
                tint: .green,
                kind: .page(AnyView(HelpScreen(sendFeedback: sendFeedback, rate: rate)))
            ),
            SettingsEntry(
                id: "settings-rate",
                title: String(localized: "Rate Zeitkonto"),
                detail: String(localized: "On the App Store"),
                keywords: String(localized: "rate, review, App Store", comment: "Settings search words for Rate Zeitkonto"),
                systemImage: "star",
                tint: .yellow,
                kind: .action(rate)
            ),
            SettingsEntry(
                id: "settings-feedback",
                title: String(localized: "Send feedback"),
                detail: String(localized: "A mail to the developer"),
                keywords: String(localized: "feedback, mail, contact, support", comment: "Settings search words for Send feedback"),
                systemImage: "envelope",
                tint: .blue,
                kind: .action(sendFeedback)
            ),
        ]
    }

    /// Screens one level down, found by the search only.
    var deeperEntries: [SettingsEntry] {
        var entries = [
            SettingsEntry(
                id: "settings-allowance",
                title: String(localized: "Allowance & travel"),
                detail: settings.allowance.isEnabled ? String(localized: "On") : String(localized: "Off"),
                keywords: String(localized: "allowance, field allowance, km, kilometres, travel, mileage", comment: "Settings search words for Allowance & travel"),
                systemImage: "car",
                tint: .green,
                kind: .page(AnyView(AllowanceSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-day-types",
                title: String(localized: "Day types"),
                detail: "\(settings.dayTypeCatalog.all.count)",
                keywords: String(localized: "day types, sick, vacation, bad weather", comment: "Settings search words for Day types"),
                systemImage: "tag",
                tint: .purple,
                kind: .page(AnyView(DayTypeSettingsScreen()))
            ),
            SettingsEntry(
                id: "settings-data",
                title: String(localized: "Backup and data"),
                detail: nil,
                keywords: String(localized: "backup, restore, delete everything, file", comment: "Settings search words for Backup and data"),
                systemImage: "externaldrive",
                tint: .gray,
                kind: .page(AnyView(DataSettingsScreen()))
            ),
        ]
        if settings.features.trackHolidays {
            entries.append(SettingsEntry(
                id: "settings-holidays",
                title: String(localized: "Public holidays"),
                detail: settings.publicHolidays.addedSet.map(PublicHolidayActions.title(of:)),
                keywords: String(localized: "public holidays, holidays, country", comment: "Settings search words for Holidays"),
                systemImage: "flag",
                tint: .red,
                kind: .page(AnyView(HolidaySettingsScreen()))
            ))
        }
        return entries
    }

    // MARK: - What each row says it is set to

    private var settings: AppSettings { settingsStore.settings }
    private var today: CalendarDate { CalendarDate.today(in: settingsStore.workCalendar) }

    private var setupText: SiteSetupText {
        SiteSetupText(
            formatting: settingsStore.dateFormatting,
            durations: settings.displayFormatting,
            calendar: settingsStore.workCalendar
        )
    }

    private var jobsSummary: String {
        let jobs = settings.activeJobs
        return jobs.count == 1 ? jobs[0].displayName() : "\(jobs.count)"
    }

    /// "42h 30m a week", for the week in force today.
    private var scheduleSummary: String {
        let schedule = settings.primarySchedule(on: today)
        guard (1...7).contains(where: { schedule.isWorkingWeekday($0) }) else {
            return String(localized: "No working days")
        }
        return String(
            localized: "\(settings.displayFormatting.string(schedule.weeklyTargetMinutes)) a week",
            comment: "Settings, Working hours; the value is the hours of a week, such as 42h 30m"
        )
    }

    /// The running balance, "+12h 40m"; while it is not counted, that it
    /// is off.
    private var calculationSummary: String {
        guard settings.features.showsBalance && settings.features.autoCalculateOvertime else {
            return String(localized: "Overtime off")
        }
        guard let minutes = figures.balanceMinutes else { return settings.rounding.title }
        return settings.displayFormatting.signedString(minutes)
    }

    /// "9,50 €/h", or that none is set.
    private var paySummary: String {
        guard let rules = settings.primaryJob.pay?.value(on: today) else {
            return String(localized: "Not set")
        }
        return String(
            localized: "\(settings.money.string(rules.hourlyRateCents))/h",
            comment: "Settings, the hourly rate; the value is an amount of money, such as 9,50 €"
        )
    }

    /// "8 days left", or the year's allowance before it is worked out.
    private var leaveSummary: String {
        if let left = figures.leaveLeft {
            return String(
                localized: "\(left.localized) days left",
                comment: "Settings, the Leave row; the value is a number of days, such as 8 or 2.5"
            )
        }
        return String(
            localized: "\(HalfDays(days: settings.leave.allowanceDays).localized) days a year",
            comment: "Settings, the leave row; the value is a number of days"
        )
    }

    /// "07:00–16:00 · 30m break".
    private var newSitesSummary: String {
        setupText.usualDay(settings.newSites.setup(schedule: settings.primarySchedule(on: today)))
    }

    private var remindersSummary: String {
        let reminders = settings.reminders
        let anyOn = reminders.isEnabled || reminders.siteRemindersEnabled
            || reminders.monthlySheetEnabled || reminders.unsentWorkEnabled
        return anyOn ? String(localized: "On") : String(localized: "Off")
    }

    /// "Croatia", or how many day types there are.
    private var dayTypesSummary: String {
        if settings.features.trackHolidays, let set = settings.publicHolidays.addedSet {
            return PublicHolidayActions.title(of: set)
        }
        return String(
            localized: "\(settings.dayTypeCatalog.all.count) types",
            comment: "Settings, Day types & holidays; the value is how many day types there are"
        )
    }

    private var icloudSummary: String {
        guard SyncPreference.offer != .hidden else { return String(localized: "Backup file") }
        return HoursStack.isSyncing ? String(localized: "Syncing") : String(localized: "iCloud off · backup file")
    }

    private var fieldsSummary: String {
        var enabled: [String] = []
        if settings.features.trackBreaks { enabled.append(String(localized: "breaks")) }
        if settings.features.trackOvertime { enabled.append(String(localized: "overtime")) }
        if settings.features.trackNotes { enabled.append(String(localized: "notes")) }
        if settings.features.trackLocation { enabled.append(String(localized: "location")) }
        if settings.features.trackTags { enabled.append(String(localized: "tags")) }
        return enabled.isEmpty
            ? String(localized: "None")
            : enabled.joined(separator: ", ").capitalizedFirstLetter
    }
}

/// A group of the index.
struct SettingsGroup: Identifiable {
    let id: String
    let title: String
    let entries: [SettingsEntry]
}

/// One setting: a row in its group, and what the search looks through.
struct SettingsEntry: Identifiable {
    /// The row's accessibility identifier, which the UI tests use.
    let id: String
    let title: String
    /// What it is set to now, in grey on the right.
    let detail: String?
    /// Other words it is known by, comma separated, in the app's language.
    let keywords: String
    let systemImage: String
    let tint: Color
    let kind: Kind

    enum Kind {
        case page(AnyView)
        case action(() -> Void)
    }

    /// Title, value and keywords, folded for matching.
    var searchText: String {
        Self.fold([title, detail ?? "", keywords].joined(separator: " "))
    }

    /// Case and accents aside: "Überstunden" is found by "uberstunden".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// An index row that opens its screen or does its action, with the
/// identifier the UI tests use on the control itself.
struct SettingsEntryLink: View {
    let entry: SettingsEntry

    var body: some View {
        switch entry.kind {
        case let .page(destination):
            NavigationLink {
                destination
            } label: {
                SettingsIndexRow(entry: entry)
            }
            .accessibilityIdentifier(entry.id)
            .id(entry.id)
            .tourTarget(entry.id == SettingsIndex.exportRow ? .settingsExport : nil)
        case let .action(perform):
            Button(action: perform) {
                SettingsIndexRow(entry: entry)
            }
            .tint(.primary)
            .accessibilityIdentifier(entry.id)
        }
    }
}

/// A settings row as the mockup draws it: a coloured square with a symbol,
/// the title, and on the right in grey what it is set to. At the large
/// accessibility sizes the value goes under the title instead.
struct SettingsIndexRow: View {
    let entry: SettingsEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: entry.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(entry.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    value
                }
            } else {
                title
                Spacer(minLength: Metrics.small)
                value
            }
        }
        .frame(minHeight: 44)
    }

    private var title: some View {
        Text(verbatim: entry.title)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var value: some View {
        if let detail = entry.detail, !detail.isEmpty {
            Text(verbatim: detail)
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// A settings row: what it is on the left, what it is set to on the right.
/// The rows inside the settings screens; the index uses `SettingsIndexRow`.
struct SettingsRow: View {
    let title: String
    var value: String?
    var systemImage: String?

    var body: some View {
        HStack(spacing: Metrics.medium) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
            }
            Text(title)
            Spacer(minLength: Metrics.small)
            if let value {
                Text(value)
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(1)
            }
        }
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
