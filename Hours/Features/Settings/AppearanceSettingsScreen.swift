import SwiftUI

struct AppearanceSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: settingsStore.binding(\.appearance)) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                Picker("Durations", selection: settingsStore.binding(\.displayDurationStyle)) {
                    ForEach(DurationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            } header: {
                Text("Durations in the app")
            } footer: {
                Text("How hours are written throughout the app. Exports have their own setting.")
            }

            Section {
                Toggle("Bigger buttons", isOn: settingsStore.binding(\.biggerButtons))
                    .accessibilityIdentifier("appearance-bigger-buttons")
                Toggle("High contrast", isOn: settingsStore.binding(\.highContrast))
                    .accessibilityIdentifier("appearance-high-contrast")
            } header: {
                Text("On site")
            } footer: {
                Text("Bigger buttons make the daily actions easier to hit with gloves on.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
