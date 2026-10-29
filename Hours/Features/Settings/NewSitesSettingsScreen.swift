import SwiftUI

/// Settings › New sites start with (1.2): the usual day, work days and
/// extras every new site gets — the wizard's "Start fresh", and any other
/// way a site is added. Until something here is changed it follows the
/// working week; "Follow my working hours" goes back to that.
///
/// Stored in `AppSettings.newSites`, which a backup carries.
struct NewSitesSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                UsualDayRows(
                    start: timeBinding(\.start, resolved: \.start),
                    end: timeBinding(\.end, resolved: \.end),
                    breakMinutes: Binding(
                        get: { resolved.breakMinutes },
                        set: { minutes in settingsStore.update { $0.newSites.breakMinutes = minutes } }
                    ),
                    calendar: settingsStore.workCalendar
                )
            } header: {
                Text("Usual day")
            } footer: {
                Text("A new day on a site starts with these times for everyone ticked.")
            }

            Section {
                WorkDaysPicker(
                    days: Binding(
                        get: { resolved.workDays },
                        set: { days in settingsStore.update { $0.newSites.workDays = days } }
                    ),
                    formatting: settingsStore.dateFormatting
                )
            } header: {
                Text("Work days")
            } footer: {
                Text("Reminders only nag on a site's work days.")
            }

            Section {
                SiteExtrasRows(
                    setup: extrasBinding,
                    allowanceByDefault: Binding(
                        get: { settingsStore.settings.newSites.allowanceByDefault },
                        set: { on in settingsStore.update { $0.newSites.allowanceByDefault = on } }
                    ),
                    showsDiary: false
                )
            } header: {
                Text("Extras")
            } footer: {
                Text("Each site can change these in its own settings.")
            }

            if followsChanges {
                Section {
                    Button("Follow my working hours") {
                        settingsStore.update {
                            $0.newSites.start = nil
                            $0.newSites.end = nil
                            $0.newSites.breakMinutes = nil
                            $0.newSites.workDays = nil
                        }
                    }
                    .accessibilityIdentifier("new-sites-follow-schedule")
                } footer: {
                    Text("Takes the start, end, break and work days from Settings › Working hours again.")
                }
            }
        }
        .navigationTitle("New sites start with")
        .accessibilityIdentifier("screen-new-sites")
    }

    /// What a new site would get now.
    private var resolved: SiteSetup {
        let settings = settingsStore.settings
        return settings.newSites.setup(
            schedule: settings.primarySchedule(on: CalendarDate.today(in: settingsStore.workCalendar))
        )
    }

    /// Something here no longer follows the working week.
    private var followsChanges: Bool {
        let defaults = settingsStore.settings.newSites
        return defaults.start != nil || defaults.end != nil || defaults.breakMinutes != nil || defaults.workDays != nil
    }

    private func timeBinding(
        _ keyPath: WritableKeyPath<NewSiteDefaults, TimeOfDay?>,
        resolved resolvedPath: KeyPath<SiteSetup, TimeOfDay?>
    ) -> Binding<TimeOfDay> {
        Binding(
            get: { resolved[keyPath: resolvedPath] ?? TimeOfDay(hour: 7, minute: 0) },
            set: { time in settingsStore.update { $0.newSites[keyPath: keyPath] = time } }
        )
    }

    /// The switches, written back one by one.
    private var extrasBinding: Binding<SiteSetup> {
        Binding(
            get: { resolved },
            set: { setup in
                settingsStore.update {
                    $0.newSites.asksKilometres = setup.asksKilometres
                    $0.newSites.eveningReminder = setup.eveningReminder
                    $0.newSites.monthlySheet = setup.monthlySheet
                }
            }
        )
    }
}
