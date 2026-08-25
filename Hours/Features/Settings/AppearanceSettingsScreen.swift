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
                Text("Durations")
            } footer: {
                Text("How hours are written throughout the app. Exports have their own setting.")
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
