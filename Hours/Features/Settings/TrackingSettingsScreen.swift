import SwiftUI

/// Which fields exist.
///
/// Switching something off removes it from the day editor, from the calendar,
/// from the statistics and from the export column list — it does not grey
/// anything out.
struct TrackingSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                Text("Switch off what you never use and the day screen gets shorter.")
                    .foregroundStyle(.hoursSecondaryText)
            }

            Section {
                Toggle("Clock in and out", isOn: settingsStore.binding(\.features.useTimeClock))
                Toggle("Breaks", isOn: settingsStore.binding(\.features.trackBreaks))
                if settingsStore.settings.features.trackBreaks {
                    Toggle("Several breaks a day", isOn: settingsStore.binding(\.features.multipleBreaksPerDay))
                }
            } header: {
                Text("Recording")
            } footer: {
                Text("Clock in and out adds a button on today that starts and stops a clock. With several breaks switched on, each can be a length or a pair of times.")
            }

            Section {
                Toggle("Expected hours", isOn: settingsStore.binding(\.features.trackExpectedHours))
                if settingsStore.settings.features.trackExpectedHours {
                    Toggle("Overtime and balance", isOn: settingsStore.binding(\.features.trackOvertime))
                    Toggle("Expected hours per day", isOn: settingsStore.binding(\.features.allowPerDayExpectedOverride))
                    Toggle("Manual adjustments", isOn: settingsStore.binding(\.features.allowManualAdjustments))
                }
                Toggle("Public holidays and days off", isOn: settingsStore.binding(\.features.trackHolidays))
            } header: {
                Text("Hours and balance")
            } footer: {
                Text("Overtime needs expected hours to measure against, so it follows that setting.")
            }

            Section("Extra fields") {
                Toggle("Notes", isOn: settingsStore.binding(\.features.trackNotes))
                Toggle("Location", isOn: settingsStore.binding(\.features.trackLocation))
                Toggle("Tags", isOn: settingsStore.binding(\.features.trackTags))
            }
        }
        .navigationTitle("Fields")
        .navigationBarTitleDisplayMode(.inline)
    }
}
