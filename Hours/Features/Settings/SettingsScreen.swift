import SwiftUI

/// The settings index.
///
/// Grouped by what you are changing rather than by which type holds it, and
/// each row says what it currently is, so the common case — checking a setting
/// — does not need a tap.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isShowingPaywall = true
                    } label: {
                        SettingsRow(
                            title: subscriptions.isPro ? "Zeitkonto Pro" : "Unlock Zeitkonto Pro",
                            value: subscriptions.isPro ? "Active" : nil,
                            systemImage: subscriptions.isPro ? "checkmark.seal" : "sparkles"
                        )
                    }
                    .tint(.primary)
                } footer: {
                    if !subscriptions.isPro {
                        Text("Timesheets, widgets, a second job, range editing and iCloud sync. Recording your hours is free and stays free.")
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
                            title: String(localized: "Calculation"),
                            value: settings.durationPolicy.title,
                            systemImage: "function"
                        )
                    }
                }

                Section("Tracking") {
                    NavigationLink {
                        TrackingSettingsScreen()
                    } label: {
                        SettingsRow(title: "Fields", value: fieldsSummary, systemImage: "slider.horizontal.3")
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
                    NavigationLink {
                        ReminderSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "Reminders"),
                            value: settings.reminders.isEnabled ? "On" : "Off",
                            systemImage: "bell"
                        )
                    }
                    if settings.features.trackHolidays {
                        NavigationLink {
                            HolidaySettingsScreen()
                        } label: {
                            SettingsRow(title: "Holidays", value: nil, systemImage: "flag")
                        }
                    }
                }

                Section("Appearance") {
                    NavigationLink {
                        CalendarSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "Calendar"),
                            value: settings.calendar.showWeekends ? "All days" : "Weekdays only",
                            systemImage: "square.grid.3x3"
                        )
                    }
                    NavigationLink {
                        AppearanceSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "Theme"),
                            value: settings.appearance.title,
                            systemImage: "circle.lefthalf.filled"
                        )
                    }
                }

                Section("Export") {
                    NavigationLink {
                        ExportSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "Export options"),
                            value: "\(settings.effectiveExportColumns.count) columns",
                            systemImage: "tablecells"
                        )
                    }
                }

                Section("Data") {
                    NavigationLink {
                        SyncSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "iCloud"),
                            value: HoursStack.isSyncing ? "On" : "Off",
                            systemImage: "icloud"
                        )
                    }
                    NavigationLink {
                        DataSettingsScreen()
                    } label: {
                        SettingsRow(title: "Backup and data", value: nil, systemImage: "externaldrive")
                    }
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        SettingsRow(title: "Privacy", value: nil, systemImage: "hand.raised")
                    }
                }
            }
            .sheet(isPresented: $isShowingPaywall) { PaywallSheet() }
            .navigationTitle("Settings")
        }
    }

    @State private var isShowingPaywall = false

    private var settings: AppSettings { settingsStore.settings }

    private var jobsSummary: String {
        let jobs = settings.activeJobs
        return jobs.count == 1 ? jobs[0].name : "\(jobs.count)"
    }

    private var scheduleSummary: String {
        let weekly = settings.primarySchedule.weeklyTargetMinutes
        let days = settings.primarySchedule.workingDaysPerWeek
        let total = settings.displayFormatting.string(weekly)
        return String(inflected: "\(total) over ^[\(days) day](inflect: true)")
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
