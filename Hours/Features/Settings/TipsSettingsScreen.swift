import SwiftUI

/// Settings › More › Tips (2026-11-05): the switch for the hints at the top
/// of a screen, and bringing back the ones hidden with ✕.
struct TipsSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Show tips", isOn: settingsStore.binding(\.tips.isEnabled))
                    .accessibilityIdentifier("settings-tips-show")
                Button("Show all tips again") {
                    settingsStore.update { $0.tips.showAllAgain() }
                }
                .disabled(!settingsStore.settings.tips.hasDismissed)
                .accessibilityIdentifier("settings-tips-reset")
            } footer: {
                Text("Short hints at the top of a screen, shown only when they apply.")
            }
        }
        // A screen the UI tests wait for, on the form.
        .accessibilityIdentifier("screen-settings-tips")
        .navigationTitle("Tips")
        .navigationBarTitleDisplayMode(.inline)
    }
}
