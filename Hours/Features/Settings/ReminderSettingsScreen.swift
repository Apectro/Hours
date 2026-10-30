import SwiftUI

/// The weekly nudge about days with nothing recorded, and for someone with a
/// site, the evening site reminder, the note on the 1st about the sheet, and
/// the weekly note about extra work not sent to the boss yet.
struct ReminderSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var authorizationDenied = false
    @State private var siteAuthorizationDenied = false
    @State private var sheetAuthorizationDenied = false
    @State private var unsentAuthorizationDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Remind me about gaps", isOn: enabledBinding)
                if settings.reminders.isEnabled {
                    Picker("Day", selection: settingsStore.binding(\.reminders.weekday)) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(settingsStore.dateFormatting.weekdayName(for: weekday)).tag(weekday)
                        }
                    }
                    DatePicker("At", selection: timeBinding, displayedComponents: .hourAndMinute)
                    Stepper(
                        String(
                            localized: "Look back \(settings.reminders.lookBackDays) days",
                            comment: "How far back the gap reminder checks for missing hours"
                        ),
                        value: settingsStore.binding(\.reminders.lookBackDays),
                        in: 1...90
                    )
                }
            } header: {
                Text("Your own hours")
            } footer: {
                Text(authorizationDenied
                     ? "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working."
                     : "A weekly note if a working day has no hours. Days off and days you excluded never count as missing.")
            }

            // Only for someone who has a site; the rest never need to know.
            if hasSites {
                Section {
                    Toggle("Leaving: write today's hours", isOn: siteEnabledBinding)
                    if settings.reminders.siteRemindersEnabled {
                        DatePicker("At", selection: siteTimeBinding, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Monthly sheet on the 1st", isOn: sheetEnabledBinding)
                    if settings.reminders.monthlySheetEnabled {
                        DatePicker("At", selection: sheetTimeBinding, displayedComponents: .hourAndMinute)
                    }
                    // Off by default: not everyone with a site writes extra work.
                    Toggle("Extra work not sent", isOn: unsentEnabledBinding)
                    if settings.reminders.unsentWorkEnabled {
                        Picker("Day", selection: unsentWeekdayBinding) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(settingsStore.dateFormatting.weekdayName(for: weekday)).tag(weekday)
                            }
                        }
                        DatePicker("At", selection: unsentTimeBinding, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Sites")
                } footer: {
                    Text(siteAuthorizationDenied || sheetAuthorizationDenied || unsentAuthorizationDenied
                         ? "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working."
                         : "In the evening, a note when a site day you normally write is still missing. On the 1st, a note that last month's site sheets are ready. Once a week, a note about finished extra work not sent to your boss. The arrival reminder is in each site's settings.")
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

    /// Same promise as the other toggles.
    private var unsentEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.reminders.unsentWorkEnabled },
            set: { isOn in
                guard isOn else {
                    settingsStore.update { $0.reminders.unsentWorkEnabled = false }
                    unsentAuthorizationDenied = false
                    ReminderScheduler().cancelUnsentWorkReminder()
                    return
                }
                Task {
                    let granted = await ReminderScheduler().requestAuthorization()
                    unsentAuthorizationDenied = !granted
                    settingsStore.update { $0.reminders.unsentWorkEnabled = granted }
                    if granted { await refreshUnsentWork() }
                }
            }
        )
    }

    private var unsentWeekdayBinding: Binding<Int> {
        Binding(
            get: { settings.reminders.unsentWorkWeekday },
            set: { weekday in
                settingsStore.update { $0.reminders.unsentWorkWeekday = weekday }
                Task { await refreshUnsentWork() }
            }
        )
    }

    private var unsentTimeBinding: Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: {
                OptionalTimeRow.date(from: settings.reminders.unsentWorkTime, in: calendar)
            },
            set: { date in
                let time = OptionalTimeRow.time(from: date, in: calendar)
                settingsStore.update { $0.reminders.unsentWorkTime = time }
                Task { await refreshUnsentWork() }
            }
        )
    }

    private func refreshUnsentWork() async {
        await ExtraWorkReminderRefresher.refresh(context: modelContext, settingsStore: settingsStore)
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
