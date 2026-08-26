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
                    title: String(localized: "Only what you export"),
                    detail: String(localized: "Files you create in Export go through the system share sheet, and you choose where they go.")
                )
                if isSyncing {
                    PrivacyPoint(
                        symbol: "icloud",
                        title: String(localized: "Your own iCloud"),
                        detail: String(localized: "You turned sync on, so your days, holidays and settings are kept in your private iCloud storage. Only your devices, signed in as you, can read it. Turn it off in Settings › iCloud.")
                    )
                } else {
                    PrivacyPoint(
                        symbol: "icloud.slash",
                        title: String(localized: "No sync"),
                        detail: String(localized: "iCloud syncing is off. Your data lives in this app's own storage and is included in an encrypted device backup if you make one. You can turn sync on in Settings › iCloud.")
                    )
                }
                PrivacyPoint(
                    symbol: "location.slash",
                    title: String(localized: "No location access"),
                    detail: String(localized: "The optional location field is a text note you type. The app never asks the system where you are.")
                )
                PrivacyPoint(
                    symbol: "creditcard",
                    title: String(localized: "Buying Hours Pro"),
                    detail: String(localized: "Payment is handled entirely by the App Store, the way every purchase on your phone is. Hours is told one thing in return — whether it has been paid for — and never sees your name, your email or your card. There is still nothing to sign into.")
                )
            }

            Section("Keeping your data safe") {
                PrivacyPoint(
                    symbol: "externaldrive",
                    title: String(localized: "Make a backup"),
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
        let common = "There is no account to make, no server of ours, no analytics, no advertising and no third-party code."
        // The App Store half is stated in both branches. Hours talks to Apple
        // to ask whether Pro has been paid for, so the old line about making no
        // network connections at all stopped being true the day it could be
        // bought — and this is the worst screen in the app to leave a stale
        // promise on.
        let purchases = "The one thing it asks the network is whether Hours Pro has been paid for, which it asks the App Store; no part of your hours goes with the question."
        return isSyncing
            ? "Your hours are kept on this device and in your own private iCloud storage, which only your devices can read. \(common) \(purchases)"
            : "Your hours are stored locally and nowhere else. \(common) \(purchases)"
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
