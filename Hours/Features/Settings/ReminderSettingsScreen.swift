import SwiftUI

/// The weekly nudge about days with nothing recorded.
struct ReminderSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var authorizationDenied = false

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
                        "Look back \(settings.reminders.lookBackDays) days",
                        value: settingsStore.binding(\.reminders.lookBackDays),
                        in: 1...90
                    )
                } footer: {
                    Text("How far back to check. Days you have marked as excluded, and days that are not working days, are never counted as missing.")
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settings: AppSettings { settingsStore.settings }

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
