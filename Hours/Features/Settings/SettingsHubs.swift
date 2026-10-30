import SwiftUI
import SwiftData

/// Settings › Day types & holidays (1.2 redesign, board 17): the day types
/// themselves, each a tap from its editor, and under them the public
/// holidays and your own days off.
struct DayTypesAndHolidaysScreen: View {
    var body: some View {
        DayTypeSettingsScreen(showsHolidays: true)
            .accessibilityIdentifier("screen-day-types-holidays")
    }
}

/// The Holidays group of Day types & holidays: the country's public
/// holidays and the days off you added yourself, both on the Public
/// holidays screen.
struct HolidayRowsSection: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext
    @Query private var holidays: [HolidayRecord]

    var body: some View {
        Section {
            NavigationLink {
                HolidaySettingsScreen()
            } label: {
                SettingsRow(title: String(localized: "Public holidays"), value: publicValue, systemImage: "flag")
            }
            .accessibilityIdentifier("settings-holidays")
            NavigationLink {
                HolidaySettingsScreen()
            } label: {
                SettingsRow(title: String(localized: "Your own days off"), value: "\(ownCount)", systemImage: "calendar.badge.plus")
            }
            .accessibilityIdentifier("settings-own-holidays")
        } header: {
            Text("Holidays")
        } footer: {
            Text("Public holidays for your country, and your own days off.")
        }
    }

    /// The added rules, by what the public set says it added.
    private var publicIDs: Set<UUID> {
        Set(settingsStore.settings.publicHolidays.rulesToRemove(from: holidays.map(\.rule)))
    }

    /// "Croatia · 14", or that none were added.
    private var publicValue: String {
        guard let set = settingsStore.settings.publicHolidays.addedSet else {
            return String(localized: "None")
        }
        return "\(PublicHolidayActions.title(of: set)) · \(publicIDs.count)"
    }

    private var ownCount: Int {
        let ids = publicIDs
        return holidays.filter { !ids.contains($0.identifier) }.count
    }
}

/// Settings › iCloud & backup (1.2 redesign, board 19): sync, and the
/// backup file that is the copy which survives a lost phone, side by side.
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
                            title: String(localized: "Sync with iCloud"),
                            value: HoursStack.isSyncing ? String(localized: "On") : String(localized: "Off"),
                            systemImage: "icloud"
                        )
                    }
                    .accessibilityIdentifier("settings-icloud")
                    LabeledContent("Right now") {
                        Text(HoursStack.isSyncing ? "Syncing" : "This device only")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                } footer: {
                    Text("Your hours on your iPhone and iPad, and safe if you lose your phone.")
                }
            }
            Section {
                NavigationLink {
                    DataSettingsScreen()
                } label: {
                    SettingsRow(title: String(localized: "Backup and data"), value: nil, systemImage: "externaldrive")
                }
                .accessibilityIdentifier("settings-data")
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup file with everything in it, restoring one, and deleting everything.")
            }
        }
        .navigationTitle("iCloud & backup")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-icloud-backup")
    }
}

/// Settings › Help & tour (1.2 redesign, board 19): the guided tour again,
/// what is where now, and the ways to say something back.
struct HelpScreen: View {
    /// The same actions as the rows under More.
    var sendFeedback: () -> Void = {}
    var rate: () -> Void = {}

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    // Back first: the tour starts on the Today tab.
                    dismiss()
                    tour?.start(leadsCrew: settingsStore.settings.leadsCrew)
                } label: {
                    HStack(spacing: Metrics.medium) {
                        SettingsRow(
                            title: String(localized: "Show the tour again"),
                            value: String(localized: "1 min"),
                            systemImage: "questionmark.circle"
                        )
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .tint(.primary)
                .accessibilityIdentifier("settings-show-tour")
            } footer: {
                Text("Six stops around the app.")
            }

            Section {
                place("Write today", where: "Today", systemImage: "sun.max")
                place("Your crew's day", where: "Sites › a site", systemImage: "person.3")
                place("Monthly sheet", where: "Sites › Sheet", systemImage: "tablecells")
                place("Extra work for the boss", where: "a site day", systemImage: "hammer")
                place("Overtime and balance", where: "Insights", systemImage: "chart.bar")
                place("Every setting", where: "Settings › Search", systemImage: "gearshape")
            } header: {
                Text("What is where")
            }

            Section {
                Button(action: sendFeedback) {
                    SettingsRow(title: String(localized: "Send feedback"), value: nil, systemImage: "envelope")
                        .frame(minHeight: 44)
                }
                .tint(.primary)
                .accessibilityIdentifier("help-feedback")
                Button(action: rate) {
                    SettingsRow(title: String(localized: "Rate Zeitkonto"), value: nil, systemImage: "star")
                        .frame(minHeight: 44)
                }
                .tint(.primary)
                .accessibilityIdentifier("help-rate")
            }
        }
        .navigationTitle("Help & tour")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-help")
    }

    /// "Write today — Today": a thing you do, and where it is.
    private func place(_ title: LocalizedStringKey, where place: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(.hoursSecondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                    Spacer(minLength: Metrics.small)
                    Text(place)
                        .foregroundStyle(.hoursSecondaryText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(place)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
