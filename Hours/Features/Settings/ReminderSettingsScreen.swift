import SwiftUI

/// The weekly nudge about days with nothing recorded, and for someone with a
/// site, the evening site reminder and the note on the 1st about the sheet.
struct ReminderSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var authorizationDenied = false
    @State private var siteAuthorizationDenied = false
    @State private var sheetAuthorizationDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Remind me about gaps", isOn: enabledBinding)
            } footer: {
                Text(authorizationDenied
                     ? "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working."
                     : "The calendar already marks a working day with nothing on it. This tells you without having to look.")
            }

            if settings.reminders.isEnabled {
                Section("When") {
                    Picker("Day", selection: settingsStore.binding(\.reminders.weekday)) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(settingsStore.dateFormatting.weekdayName(for: weekday)).tag(weekday)
                        }
                    }
                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }

                Section {
                    Stepper(
                        String(
                localized: "Look back \(settings.reminders.lookBackDays) days",
                comment: "How far back the gap reminder checks for missing hours"
            ),
                        value: settingsStore.binding(\.reminders.lookBackDays),
                        in: 1...90
                    )
                } footer: {
                    Text("How far back to check. Days you have marked as excluded, and days that are not working days, are never counted as missing.")
                }
            }

            // Only for someone who has a site; the rest never need to know.
            if hasSites {
                Section {
                    Toggle("Site reminders", isOn: siteEnabledBinding)
                    if settings.reminders.siteRemindersEnabled {
                        DatePicker("Time", selection: siteTimeBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(siteAuthorizationDenied
                         ? "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working."
                         : "In the evening, a note that a site day you normally write is still missing. Writing the day removes it.")
                }

                Section {
                    Toggle("Monthly sheet for the director", isOn: sheetEnabledBinding)
                    if settings.reminders.monthlySheetEnabled {
                        DatePicker("Time", selection: sheetTimeBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text(sheetAuthorizationDenied
                         ? "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working."
                         : "On the 1st, a note for each site you worked on last month that its sheet is ready to send. Tapping it opens the sheet.")
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settings: AppSettings { settingsStore.settings }

    private var hasSites: Bool {
        !SiteRepository(context: modelContext).sites(includeArchived: true).isEmpty
    }

    /// Same promise as the weekly toggle: it only stays on if the system will
    /// let it fire.
    private var siteEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminders.siteRemindersEnabled },
            set: { isOn in
                guard isOn else {
                    settingsStore.update { $0.reminders.siteRemindersEnabled = false }
                    siteAuthorizationDenied = false
                    Task { await ReminderScheduler().cancelSiteReminders() }
                    return
                }
                Task {
                    let granted = await ReminderScheduler().requestAuthorization()
                    siteAuthorizationDenied = !granted
                    settingsStore.update { $0.reminders.siteRemindersEnabled = granted }
                    if granted { await refreshSiteReminders() }
                }
            }
        )
    }

    /// Same promise as the other two toggles.
    private var sheetEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminders.monthlySheetEnabled },
            set: { isOn in
                guard isOn else {
                    settingsStore.update { $0.reminders.monthlySheetEnabled = false }
                    sheetAuthorizationDenied = false
                    Task { await ReminderScheduler().cancelMonthlySheetReminders() }
                    return
                }
                Task {
                    let granted = await ReminderScheduler().requestAuthorization()
                    sheetAuthorizationDenied = !granted
                    settingsStore.update { $0.reminders.monthlySheetEnabled = granted }
                    if granted { await refreshMonthlySheets() }
                }
            }
        )
    }

    private var sheetTimeBinding: Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: {
                OptionalTimeRow.date(from: settings.reminders.monthlySheetTime, in: calendar)
            },
            set: { date in
                let time = OptionalTimeRow.time(from: date, in: calendar)
                settingsStore.update { $0.reminders.monthlySheetTime = time }
                Task { await refreshMonthlySheets() }
            }
        )
    }

    private func refreshMonthlySheets() async {
        await MonthlySheetRefresher.refresh(context: modelContext, settingsStore: settingsStore)
    }

    private func refreshSiteReminders() async {
        await SiteReminderRefresher.refresh(
            context: modelContext,
            preferences: settings.reminders,
            calendar: settingsStore.workCalendar
        )
    }

    private var siteTimeBinding: Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: {
                OptionalTimeRow.date(from: settings.reminders.siteReminderTime, in: calendar)
            },
            set: { date in
                let time = OptionalTimeRow.time(from: date, in: calendar)
                settingsStore.update { $0.reminders.siteReminderTime = time }
                Task { await refreshSiteReminders() }
            }
        )
    }

    /// Switching it on asks for permission first, and switches itself back off
    /// if permission is refused — a toggle that claims to be on while nothing
    /// can fire is worse than one that is honestly off.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminders.isEnabled },
            set: { isOn in
                guard isOn else {
                    settingsStore.update { $0.reminders.isEnabled = false }
                    ReminderScheduler().cancel()
                    return
                }
                Task {
                    let granted = await ReminderScheduler().requestAuthorization()
                    authorizationDenied = !granted
                    settingsStore.update { $0.reminders.isEnabled = granted }
                }
            }
        )
    }

    private var timeBinding: Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: {
                OptionalTimeRow.date(from: settings.reminders.time, in: calendar)
            },
            set: { date in
                let time = OptionalTimeRow.time(from: date, in: calendar)
                settingsStore.update { $0.reminders.time = time }
            }
        )
    }
}
