import SwiftUI

/// What the app does with your data — which is nothing beyond keeping it.
struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text(isSyncing ? "Your data goes to your iCloud and nowhere else." : "Everything stays on this device.")
                        .font(.headline)
                    Text(headlineDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Metrics.small)
            }

            Section("What leaves the device") {
                PrivacyPoint(
                    symbol: "square.and.arrow.up",
                    title: "Only what you export",
                    detail: "Files you create in Export go through the system share sheet, and you choose where they go."
                )
                if isSyncing {
                    PrivacyPoint(
                        symbol: "icloud",
                        title: "Your own iCloud",
                        detail: "You turned sync on, so your days, holidays and settings are kept in your private iCloud storage. Only your devices, signed in as you, can read it. Turn it off in Settings › iCloud."
                    )
                } else {
                    PrivacyPoint(
                        symbol: "icloud.slash",
                        title: "No sync",
                        detail: "iCloud syncing is off. Your data lives in this app's own storage and is included in an encrypted device backup if you make one. You can turn sync on in Settings › iCloud."
                    )
                }
                PrivacyPoint(
                    symbol: "location.slash",
                    title: "No location access",
                    detail: "The optional location field is a text note you type. The app never asks the system where you are."
                )
            }

            Section("Keeping your data safe") {
                PrivacyPoint(
                    symbol: "externaldrive",
                    title: "Make a backup",
                    detail: isSyncing
                        ? "Sync is not a backup: a day you delete is deleted on every device. A backup file is the copy that survives that. Settings › Backup and data."
                        : "Because nothing is synced, a backup file is the only copy that survives losing the device. Settings › Backup and data."
                )
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isSyncing: Bool { HoursStack.isSyncing }

    /// Written from what is actually true of this launch rather than from what
    /// the app intends in general. A privacy screen that says "nothing leaves
    /// the device" while the store is syncing is the one screen in the app it
    /// would be worst to be wrong on.
    private var headlineDetail: String {
        let common = "The app has no accounts, no servers of ours, no analytics, no advertising and no third-party code."
        return isSyncing
            ? "Your hours are kept on this device and in your own private iCloud storage, which only your devices can read. \(common)"
            : "Your hours are stored locally and nowhere else. \(common) It makes no network connections at all, so there is nothing for it to send even if it wanted to."
    }
}

private struct PrivacyPoint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.medium) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}
