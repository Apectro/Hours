import SwiftUI
import SwiftData

/// Settings › Day types & holidays (1.2): the two screens that decide what
/// a day is, under one row. Each keeps its own screen.
struct DayTypesAndHolidaysScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Query private var holidays: [HolidayRecord]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    DayTypeSettingsScreen()
                } label: {
                    SettingsRow(
                        title: String(localized: "Day types"),
                        value: "\(settingsStore.settings.dayTypeCatalog.all.count)",
                        systemImage: "tag"
                    )
                }
                .accessibilityIdentifier("settings-day-types")
            } footer: {
                Text("Work, sick, vacation, bad weather and your own: what each counts and pays.")
            }
            if settingsStore.settings.features.trackHolidays {
                Section {
                    NavigationLink {
                        HolidaySettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "Holidays"),
                            value: holidaysValue,
                            systemImage: "flag"
                        )
                    }
                    .accessibilityIdentifier("settings-holidays")
                } footer: {
                    Text("Public holidays for your country, and your own days off.")
                }
            }
        }
        .navigationTitle("Day types & holidays")
        .accessibilityIdentifier("screen-day-types-holidays")
    }

    private var holidaysValue: String {
        if let set = settingsStore.settings.publicHolidays.addedSet {
            return PublicHolidayActions.title(of: set)
        }
        return "\(holidays.count)"
    }
}

/// Settings › iCloud & backup (1.2): sync, and the backup file that is the
/// copy which survives a lost phone, side by side.
struct ICloudAndBackupScreen: View {
    var body: some View {
        List {
            // Shown in every build compiled with sync, even one not signed
            // for it, where the screen says why it cannot.
            if SyncPreference.offer != .hidden {
                Section {
                    NavigationLink {
                        SyncSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: String(localized: "iCloud"),
                            value: HoursStack.isSyncing ? String(localized: "On") : String(localized: "Off"),
                            systemImage: "icloud"
                        )
                    }
                    .accessibilityIdentifier("settings-icloud")
                } footer: {
                    Text("Your days, sites and settings on your other devices, through your own iCloud.")
                }
            }
            Section {
                NavigationLink {
                    DataSettingsScreen()
                } label: {
                    SettingsRow(title: String(localized: "Backup and data"), value: nil, systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings-data")
            } footer: {
                Text("A backup file with everything in it, restoring one, and deleting everything.")
            }
        }
        .navigationTitle("iCloud & backup")
        .accessibilityIdentifier("screen-icloud-backup")
    }
}

/// Settings › Help & tour (1.2): what is where, in a few lines, and the
/// guided tour again.
struct HelpScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                place("Today", systemImage: "sun.max", "Your days. Tap a day to see it, tap it again to write your hours. Export, for your own timesheet, is at the top.")
                place("Sites", systemImage: "building.2", "Each building site on a card. A site has buttons for its Crew, Diary, Sheet and Extra work; the gear is its settings. New site sets one up step by step.")
                place("Insights", systemImage: "chart.bar", "Your week, month and year in figures, your leave, and checking a payslip.")
                place("Settings", systemImage: "gearshape", "How Zeitkonto counts and what it prints. Search at the top finds any setting.")
            } header: {
                Text("What is where")
            }
            Section {
                Button {
                    // Back to Settings first: the tour's last stop is the
                    // Sheets row there.
                    dismiss()
                    tour?.start(leadsCrew: settingsStore.settings.leadsCrew)
                } label: {
                    SettingsRow(
                        title: String(localized: "Show the tour again"),
                        value: nil,
                        systemImage: "questionmark.circle"
                    )
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-show-tour")
            } footer: {
                Text("Six stops around the app, a minute in all.")
            }
        }
        .navigationTitle("Help & tour")
        .accessibilityIdentifier("screen-help")
    }

    private func place(_ title: LocalizedStringKey, systemImage: String, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Metrics.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.tiny)
        .accessibilityElement(children: .combine)
    }
}
