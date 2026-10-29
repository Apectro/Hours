import SwiftUI
import UIKit

/// The settings index (1.2, mockup Settings).
///
/// Grouped by what it means to you — Your work, Sites & crews, Days &
/// sheets, App — and each row says in grey what it is set to now, so
/// checking a setting does not need a tap. A search field at the top finds
/// any setting by its name, what it is set to, or a word it is known by
/// ("overtime", "km", "iCloud"), screens one level down included.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var isShowingPaywall = false
    @State private var isShowingFeedbackAddress = false

    private static let exportRow = "settings-export-options"

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                List {
                    if isSearching {
                        searchResults
                    } else {
                        proSection
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    row(entry)
                                }
                            } header: {
                                Text(verbatim: group.title)
                            }
                        }
                    }
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search settings")
                )
                // The tour's last stop is Sheets, which may be below the fold.
                .onChange(of: tour?.tour?.stop) { _, stop in
                    guard stop == .export else { return }
                    query = ""
                    withAnimation { scroller.scrollTo(Self.exportRow, anchor: .center) }
                }
                .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
                .alert("Send feedback", isPresented: $isShowingFeedbackAddress) {
                    Button("Copy address") { UIPasteboard.general.string = ReviewPrompt.feedbackAddress }
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(String(
                        localized: "No mail app is set up on this phone. Write to \(ReviewPrompt.feedbackAddress) from any mail app.",
                        comment: "Feedback without a mail account; the value is an email address"
                    ))
                }
                .navigationTitle("Settings")
                // A screen the UI tests wait for. The title beside it is translated.
                .accessibilityIdentifier("screen-settings")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ entry: SettingsEntry) -> some View {
        switch entry.kind {
        case let .page(destination):
            NavigationLink {
                destination
            } label: {
                SettingsIndexRow(entry: entry)
            }
            .accessibilityIdentifier(entry.id)
            .id(entry.id)
            .tourTarget(entry.id == Self.exportRow ? .settingsExport : nil)
        case let .action(perform):
            Button(action: perform) {
                SettingsIndexRow(entry: entry)
            }
            .tint(.primary)
            .accessibilityIdentifier(entry.id)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let found = matches
        if found.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(found) { entry in
                    row(entry)
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

    // MARK: - The index

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Every entry whose title, value or keywords hold what was typed,
    /// case and accents aside; the screens one level down included.
    private var matches: [SettingsEntry] {
        let needle = SettingsEntry.fold(query.trimmingCharacters(in: .whitespaces))
        var seen = Set<String>()
        return (groups.flatMap(\.entries) + deeperEntries).filter { entry in
            seen.insert(entry.id).inserted && entry.searchText.contains(needle)
        }
    }

    private var groups: [SettingsGroup] {
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
                    detail: String(
                        localized: "\(HalfDays(days: settings.leave.allowanceDays).localized) days a year",
                        comment: "Settings, the leave row; the value is a number of days"
                    ),
                    keywords: String(localized: "leave, vacation, holiday allowance, days off, carry over", comment: "Settings search words for Leave"),
                    systemImage: "beach.umbrella",
                    tint: .teal,
                    kind: .page(AnyView(LeaveSettingsScreen()))
                ),
                SettingsEntry(
                    id: "settings-jobs",
                    title: String(localized: "Jobs"),
                    detail: jobsSummary,
                    keywords: String(localized: "jobs, employer, second job", comment: "Settings search words for Jobs"),
                    systemImage: "bag",
                    tint: .indigo,
                    kind: .page(AnyView(JobSettingsScreen()))
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
                    detail: sheetsSummary,
                    keywords: String(localized: "export options, export, timesheet, PDF, Excel, CSV, columns, report language, name on sheet, date format", comment: "Settings search words for Sheets"),
                    systemImage: "tablecells",
                    tint: .blue,
                    kind: .page(AnyView(ExportSettingsScreen()))
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
            ]),
            SettingsGroup(id: "app", title: String(localized: "App"), entries: [
                SettingsEntry(
                    id: "settings-theme",
                    title: String(localized: "Appearance"),
                    detail: settings.appearance.title,
                    keywords: String(localized: "appearance, theme, dark, light", comment: "Settings search words for Appearance"),
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
                    kind: .page(AnyView(HelpScreen()))
                ),
                SettingsEntry(
                    id: "settings-rate",
                    title: String(localized: "Rate Zeitkonto"),
                    detail: String(localized: "On the App Store"),
                    keywords: String(localized: "rate, review, App Store", comment: "Settings search words for Rate Zeitkonto"),
                    systemImage: "star",
                    tint: .yellow,
                    kind: .action({ openURL(ReviewPrompt.writeReviewURL) })
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
            ]),
        ]
    }

    /// Screens one level down, found by the search only.
    private var deeperEntries: [SettingsEntry] {
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
                title: String(localized: "Holidays"),
                detail: settings.publicHolidays.addedSet.map(PublicHolidayActions.title(of:)),
                keywords: String(localized: "public holidays, holidays, country", comment: "Settings search words for Holidays"),
                systemImage: "flag",
                tint: .red,
                kind: .page(AnyView(HolidaySettingsScreen()))
            ))
        }
        return entries
    }

    private func sendFeedback() {
        guard let url = ReviewPromptStore.feedbackMailURL else { return }
        // No mail account set up means nothing opens; the address is shown
        // instead so it can be written to.
        openURL(url) { accepted in
            if !accepted { isShowingFeedbackAddress = true }
        }
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

    /// "Mon–Fri 8h, start 07:00"; a week of uneven days gives its total.
    private var scheduleSummary: String {
        // Today's week: a change still to come is not what you work now.
        let schedule = settings.primarySchedule(on: today)
        let days = Set((1...7).filter { schedule.isWorkingWeekday($0) })
        guard !days.isEmpty else { return String(localized: "No working days") }
        let lengths = Set(days.map { schedule.contractedMinutes(forWeekday: $0) })
        let hours = lengths.count == 1
            ? settings.displayFormatting.string(lengths.first ?? 0)
            : settings.displayFormatting.string(schedule.weeklyTargetMinutes)
        return String(
            localized: "\(setupText.workDays(days)) \(hours), start \(settingsStore.dateFormatting.time(schedule.defaultStart, on: today))",
            comment: "Settings, Working hours; the values are the working days, the hours a day (or a week) and the usual start"
        )
    }

    /// "Counting overtime · Exact".
    private var calculationSummary: String {
        let overtime = settings.features.showsBalance && settings.features.autoCalculateOvertime
            ? String(localized: "Counting overtime")
            : String(localized: "Overtime off")
        return "\(overtime) · \(settings.rounding.title)"
    }

    /// "€15.00 an hour · allowance €14.00 a day", or that none is set.
    private var paySummary: String {
        var parts: [String] = []
        if let rules = settings.primaryJob.pay?.value(on: today) {
            parts.append(String(
                localized: "\(settings.money.string(rules.hourlyRateCents)) an hour",
                comment: "Settings, the hourly rate; the value is an amount of money"
            ))
        } else {
            parts.append(String(localized: "Not set"))
        }
        if settings.allowance.isEnabled {
            if settings.allowance.dailyAllowanceCents > 0 {
                parts.append(String(
                    localized: "allowance \(settings.money.string(settings.allowance.dailyAllowanceCents)) a day",
                    comment: "Settings, the Pay row; the value is the daily field allowance"
                ))
            } else {
                parts.append(String(localized: "allowance on"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// "07:00–15:30 · 30m break · allowance on".
    private var newSitesSummary: String {
        let setup = settings.newSites.setup(schedule: settings.primarySchedule(on: today))
        var parts = [setupText.usualDay(setup)]
        if settings.allowance.isEnabled && settings.newSites.allowanceByDefault {
            parts.append(String(localized: "allowance on"))
        }
        return parts.joined(separator: " · ")
    }

    /// "Evening 18:00 · 1st of the month".
    private var remindersSummary: String {
        let reminders = settings.reminders
        var parts: [String] = []
        if reminders.siteRemindersEnabled {
            parts.append(String(
                localized: "Evening \(settingsStore.dateFormatting.time(reminders.siteReminderTime, on: today))",
                comment: "Settings, the Reminders row; the value is the evening site reminder's time"
            ))
        }
        if reminders.monthlySheetEnabled { parts.append(String(localized: "1st of the month")) }
        if reminders.isEnabled { parts.append(String(localized: "Weekly")) }
        return parts.isEmpty ? String(localized: "Off") : parts.joined(separator: " · ")
    }

    /// "Croatia · 9 types".
    private var dayTypesSummary: String {
        var parts: [String] = []
        if settings.features.trackHolidays, let set = settings.publicHolidays.addedSet {
            parts.append(PublicHolidayActions.title(of: set))
        }
        parts.append(String(
            localized: "\(settings.dayTypeCatalog.all.count) types",
            comment: "Settings, Day types & holidays; the value is how many day types there are"
        ))
        return parts.joined(separator: " · ")
    }

    /// "Croatian · Marko Horvat · 10 columns".
    private var sheetsSummary: String {
        var parts = [settings.export.language.title]
        let name = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(name.isEmpty ? String(localized: "No name yet") : name)
        parts.append(String(
            localized: "\(settings.effectiveExportColumns.count) columns",
            comment: "How many columns the export will contain"
        ))
        return parts.joined(separator: " · ")
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
private struct SettingsGroup: Identifiable {
    let id: String
    let title: String
    let entries: [SettingsEntry]
}

/// One setting: a row in its group, and what the search looks through.
struct SettingsEntry: Identifiable {
    /// The row's accessibility identifier, which the UI tests use.
    let id: String
    let title: String
    /// What it is set to now, in one grey line.
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

/// A settings row as the mockup draws it: a tinted symbol, the title, and
/// under it in grey what it is set to.
struct SettingsIndexRow: View {
    let entry: SettingsEntry

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: entry.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(entry.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.title)
                    .foregroundStyle(.primary)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minHeight: 44)
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
                    .foregroundStyle(.secondary)
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
