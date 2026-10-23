import SwiftUI

/// The settings index.
///
/// Grouped by what you are changing rather than by which type holds it, and
/// each row says what it currently is, so the common case — checking a setting
/// — does not need a tap.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                List {
                    // Nothing is sold while the first release is free
                    // (`FreeLaunch`); the row and the tester switch return with
                    // payments.
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

                    Section("Work") {
                        NavigationLink {
                            ScheduleSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Working schedule"),
                                value: scheduleSummary,
                                systemImage: "calendar.badge.clock"
                            )
                        }
                        NavigationLink {
                            LeaveSettingsScreen()
                        } label: {
                            // The allowance, as a bare number like the day types' count.
                            SettingsRow(
                                title: String(localized: "Leave"),
                                value: HalfDays(days: settings.leave.allowanceDays).localized,
                                systemImage: "beach.umbrella"
                            )
                        }
                        .accessibilityIdentifier("settings-leave")
                        NavigationLink {
                            PaySettingsScreen(jobID: settings.primaryJob.id)
                        } label: {
                            SettingsRow(
                                title: String(localized: "Pay"),
                                value: paySummary,
                                systemImage: "banknote"
                            )
                        }
                        .accessibilityIdentifier("settings-pay")
                        NavigationLink {
                            JobSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Jobs"),
                                value: jobsSummary,
                                systemImage: "bag"
                            )
                        }
                        NavigationLink {
                            CalculationSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Balance & rounding"),
                                value: settings.durationPolicy.title,
                                systemImage: "function"
                            )
                        }
                    }

                    Section("Calendar & days") {
                        NavigationLink {
                            TrackingSettingsScreen()
                        } label: {
                            SettingsRow(title: String(localized: "Fields"), value: fieldsSummary, systemImage: "slider.horizontal.3")
                        }
                        NavigationLink {
                            DayTypeSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Day types"),
                                value: "\(settings.dayTypeCatalog.all.count)",
                                systemImage: "tag"
                            )
                        }
                        if settings.features.trackHolidays {
                            NavigationLink {
                                HolidaySettingsScreen()
                            } label: {
                                SettingsRow(title: String(localized: "Holidays"), value: nil, systemImage: "flag")
                            }
                        }
                        NavigationLink {
                            CalendarSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Calendar"),
                                value: settings.calendar.showWeekends
                                    ? String(localized: "All days")
                                    : String(localized: "Weekdays only"),
                                systemImage: "square.grid.3x3"
                            )
                        }
                    }

                    // Reminders sit with what they remind you of: the site
                    // sheet on the 1st, extra work not sent, a week with gaps.
                    Section("Reports & reminders") {
                        NavigationLink {
                            ExportSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Export options"),
                                value: String(
                                    localized: "\(settings.effectiveExportColumns.count) columns",
                                    comment: "How many columns the export will contain"
                                ),
                                systemImage: "tablecells"
                            )
                        }
                        .id(Self.exportRow)
                        .tourTarget(.settingsExport)
                        NavigationLink {
                            ReminderSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Reminders"),
                                value: settings.reminders.isEnabled ? String(localized: "On") : String(localized: "Off"),
                                systemImage: "bell"
                            )
                        }
                    }

                    Section("App") {
                        NavigationLink {
                            AppearanceSettingsScreen()
                        } label: {
                            SettingsRow(
                                title: String(localized: "Theme"),
                                value: settings.appearance.title,
                                systemImage: "circle.lefthalf.filled"
                            )
                        }
                        // Shown in every build compiled with sync, even one not
                        // signed for it, where the screen says why it cannot.
                        if SyncPreference.offer != .hidden {
                            NavigationLink {
                                SyncSettingsScreen()
                            } label: {
                                SettingsRow(
                                    title: String(localized: "iCloud"),
                                    value: HoursStack.isSyncing ? String(localized: "On") : String(localized: "Off"),
                                    systemImage: "icloud"
                                )
                            }
                        }
                        NavigationLink {
                            DataSettingsScreen()
                        } label: {
                            SettingsRow(title: String(localized: "Backup and data"), value: nil, systemImage: "externaldrive")
                        }
                        NavigationLink {
                            AboutScreen()
                        } label: {
                            SettingsRow(title: String(localized: "Privacy"), value: nil, systemImage: "hand.raised")
                        }
                        .accessibilityIdentifier("settings-privacy")
                        Button {
                            tour?.start(leadsCrew: settings.leadsCrew)
                        } label: {
                            SettingsRow(
                                title: String(localized: "Show the tour again"),
                                value: nil,
                                systemImage: "questionmark.circle"
                            )
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("settings-show-tour")
                    }
                }
                // The tour's last stop is Export options, which may be below
                // the fold.
                .onChange(of: tour?.tour?.stop) { _, stop in
                    guard stop == .export else { return }
                    withAnimation { scroller.scrollTo(Self.exportRow, anchor: .center) }
                }
                .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
                .navigationTitle("Settings")
                // A screen the UI tests wait for. The title beside it is translated.
                .accessibilityIdentifier("screen-settings")
            }
        }
    }

    @State private var isShowingPaywall = false

    private static let exportRow = "settings-export-options"

    private var settings: AppSettings { settingsStore.settings }

    private var jobsSummary: String {
        let jobs = settings.activeJobs
        return jobs.count == 1 ? jobs[0].name : "\(jobs.count)"
    }

    private var scheduleSummary: String {
        // Today's week: a change still to come is not what you work now.
        let schedule = settings.primarySchedule(on: CalendarDate.today(in: settingsStore.workCalendar))
        let weekly = schedule.weeklyTargetMinutes
        let days = schedule.workingDaysPerWeek
        let total = settings.displayFormatting.string(weekly)
        return String(inflected: "\(total) over ^[\(days) day](inflect: true)")
    }

    /// The main job's rate today: "€15.00 an hour", or that none is set.
    private var paySummary: String {
        let today = CalendarDate.today(in: settingsStore.workCalendar)
        guard let rules = settings.primaryJob.pay?.value(on: today) else {
            return String(localized: "Not set")
        }
        return String(
            localized: "\(settings.money.string(rules.hourlyRateCents)) an hour",
            comment: "Settings, the hourly rate; the value is an amount of money"
        )
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

/// A settings row: what it is on the left, what it is set to on the right.
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
