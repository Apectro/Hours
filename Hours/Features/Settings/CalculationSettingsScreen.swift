import SwiftUI

/// How the numbers are worked out.
struct CalculationSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Calculate worked hours", isOn: settingsStore.binding(\.features.autoCalculateWorkedHours))
                if settingsStore.settings.features.showsBalance {
                    Toggle("Calculate overtime", isOn: settingsStore.binding(\.features.autoCalculateOvertime))
                }
            } header: {
                Text("Automatic")
            } footer: {
                Text("Switch these off to enter worked hours, or the balance, by hand on each day.")
            }

            Section {
                Picker("Rounding", selection: settingsStore.binding(\.rounding)) {
                    ForEach(RoundingRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            } header: {
                Text("Rounding")
            } footer: {
                Text("Applied to the worked total of each day, not to the times you enter.")
            }

            Section {
                Picker("Clock changes", selection: settingsStore.binding(\.durationPolicy)) {
                    ForEach(DurationPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            } header: {
                Text("Daylight saving")
            } footer: {
                Text(settingsStore.settings.durationPolicy.explanation)
            }

            Section {
                DurationStepperRow(
                    title: String(localized: "Opening balance"),
                    minutes: settingsStore.binding(\.openingBalanceMinutes),
                    range: (-500 * 60)...(500 * 60),
                    step: 30,
                    signed: true,
                    formatting: settingsStore.settings.displayFormatting
                )
                Toggle("Count from a start date", isOn: balanceStartToggle)
                if let start = settingsStore.settings.balanceStartDate {
                    DatePicker(
                        "Start date",
                        selection: balanceStartBinding(start),
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Balance")
            } footer: {
                Text("The opening balance is the overtime you were already carrying before you started using the app. Days before the start date are left out of the running balance.")
            }
        }
        .navigationTitle("Calculation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var balanceStartToggle: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.balanceStartDate != nil },
            set: { isOn in
                settingsStore.update {
                    $0.balanceStartDate = isOn ? CalendarDate.today(in: settingsStore.workCalendar) : nil
                }
            }
        )
    }

    private func balanceStartBinding(_ current: CalendarDate) -> Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: { current.date(in: calendar) },
            set: { date in
                settingsStore.update { $0.balanceStartDate = CalendarDate(date, calendar: calendar) }
            }
        )
    }
}
