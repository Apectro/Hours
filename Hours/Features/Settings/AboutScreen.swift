import SwiftUI

/// What the app does with your data — which is nothing beyond keeping it.
struct AboutScreen: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text("Everything stays on this device.")
                        .font(.headline)
                    Text("Your hours are stored locally and nowhere else. The app has no accounts, no servers, no analytics, no advertising and no third-party code. It contains no networking of any kind, so there is nothing for it to send even if it wanted to.")
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
                PrivacyPoint(
                    symbol: "icloud.slash",
                    title: "No sync",
                    detail: "iCloud syncing is not enabled. Your data lives in this app's own storage and is included in an encrypted device backup if you make one."
                )
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
                    detail: "Because nothing is synced, a backup file is the only copy that survives losing the device. Settings › Backup and data."
                )
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
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
