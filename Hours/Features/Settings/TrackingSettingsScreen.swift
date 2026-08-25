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
                Toggle("Breaks", isOn: settingsStore.binding(\.features.trackBreaks))
                if settingsStore.settings.features.trackBreaks {
                    Toggle("Several breaks a day", isOn: settingsStore.binding(\.features.multipleBreaksPerDay))
                }
            } footer: {
                Text("With several breaks switched on, each can be a length or a pair of times.")
            }

            Section {
                Toggle("Expected hours", isOn: settingsStore.binding(\.features.trackExpectedHours))
                if settingsStore.settings.features.trackExpectedHours {
                    Toggle("Overtime and balance", isOn: settingsStore.binding(\.features.trackOvertime))
                    Toggle("Per-day expected hours", isOn: settingsStore.binding(\.features.allowPerDayExpectedOverride))
                    Toggle("Manual adjustments", isOn: settingsStore.binding(\.features.allowManualAdjustments))
                }
            } header: {
                Text("Hours and balance")
            } footer: {
                Text("Overtime needs expected hours to measure against, so it follows that setting.")
            }

            Section("Holidays") {
                Toggle("Holidays", isOn: settingsStore.binding(\.features.trackHolidays))
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
