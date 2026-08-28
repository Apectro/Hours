import SwiftUI

/// Turning iCloud sync on and off.
///
/// A container's CloudKit setting is fixed at the moment the store is opened,
/// which is once per launch. So the switch records a choice and says plainly
/// that it takes effect next time, rather than appearing to work and then not.
struct SyncSettingsScreen: View {
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var isEnabled = SyncPreference.isEnabled
    @State private var paywallReason: ProFeature?

    /// What was actually opened this launch, which is what tells us whether the
    /// switch is still waiting to take effect.
    private var isSyncingNow: Bool { HoursStack.isSyncing }

    private var isPending: Bool { isEnabled != isSyncingNow }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: $isEnabled)
                    .proLock(!subscriptions.allows(.iCloudSync) && !isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        // Turning it *off* is never gated, and neither is
                        // leaving it on: a lapsed subscription must not
                        // silently strand a second device holding hours the
                        // first one no longer receives.
                        guard newValue else {
                            SyncPreference.isEnabled = false
                            return
                        }
                        guard subscriptions.allows(.iCloudSync) else {
                            isEnabled = false
                            paywallReason = .iCloudSync
                            return
                        }
                        SyncPreference.isEnabled = true
                    }
            } footer: {
                Text(
                    """
                    Your days, holidays and settings are kept on this device. \
                    Turning this on also keeps them in your own private iCloud \
                    storage, so your other devices see the same hours and \
                    count them the same way. Nothing is sent anywhere else, \
                    and there is still no account to make and no server of \
                    ours involved.
                    """
                )
            }

            if isPending {
                Section {
                    Label(
                        isEnabled
                            ? "Sync starts the next time you open Zeitkonto."
                            : "Sync stops the next time you open Zeitkonto.",
                        systemImage: "arrow.clockwise"
                    )
                    .foregroundStyle(.secondary)
                } footer: {
                    Text(
                        isEnabled
                            ? "The hours already on this device are uploaded then, and nothing is lost if you change your mind before."
                            : "Nothing is deleted from this device, and nothing is deleted from iCloud either — it simply stops being updated."
                    )
                }
            }

            Section {
                Label(
                    isSyncingNow ? "Syncing" : "This device only",
                    systemImage: isSyncingNow ? "checkmark.icloud" : "iphone"
                )
                .foregroundStyle(.secondary)
            } header: {
                Text("Right now")
            } footer: {
                // Worth saying out loud: a private database is not a backup,
                // and deleting a day on one device deletes it on all of them.
                Text(
                    """
                    Sync is not a backup. A day you delete is deleted \
                    everywhere. Settings › Backup and data writes a file that \
                    keeps a copy no sync can undo.
                    """
                )
            }
        }
        .paywall(for: $paywallReason)
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SyncSettingsScreen() }
}
