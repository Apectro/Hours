import SwiftUI

/// Turning iCloud sync on and off.
///
/// A container's CloudKit setting is fixed at the moment the store is opened,
/// which is once per launch. So the switch records a choice and says plainly
/// that it takes effect next time, rather than appearing to work and then not.
///
/// When sync could not start, this is where the app says why
/// (`SyncPreference.problem`), with the switch already off: sync never stays
/// on in a state that would stop the app from opening.
struct SyncSettingsScreen: View {
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var isEnabled = SyncPreference.isEnabled
    @State private var paywallReason: ProFeature?
    /// Why the last attempt failed, until sync is turned on again.
    @State private var problem = SyncPreference.problem
    #if DEBUG || CLOUDKIT_SCHEMA_TOOLS
    @State private var schemaOutcome = CloudKitSchema.outcome
    #endif

    private let offer = SyncPreference.offer
    private var monitor: SyncMonitor { HoursStack.syncMonitor }

    /// What was actually opened this launch, which is what tells us whether the
    /// switch is still waiting to take effect.
    private var isSyncingNow: Bool { HoursStack.isSyncing }

    private var isPending: Bool { isEnabled != isSyncingNow }

    private var canTurnOn: Bool { offer == .available }

    var body: some View {
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: $isEnabled)
                    .disabled(!canTurnOn && !isEnabled)
                    .proLock(!subscriptions.allows(.iCloudSync) && !isEnabled)
                    .accessibilityIdentifier("sync-toggle")
                    .onChange(of: isEnabled) { _, newValue in
                        // Turning it *off* is never gated, and neither is
                        // leaving it on: a lapsed subscription must not
                        // silently strand a second device holding hours the
                        // first one no longer receives.
                        guard newValue else {
                            SyncPreference.isEnabled = false
                            return
                        }
                        guard canTurnOn else {
                            isEnabled = false
                            return
                        }
                        guard subscriptions.allows(.iCloudSync) else {
                            isEnabled = false
                            paywallReason = .iCloudSync
                            return
                        }
                        SyncPreference.isEnabled = true
                        problem = nil
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

            if case .unavailable(let reason) = offer {
                Section {
                    Label(reason.sentence, systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sync-unavailable")
                }
            } else if let problem, !isEnabled {
                Section {
                    Label(problem.sentence, systemImage: "exclamationmark.icloud")
                        .foregroundStyle(Color.hoursNegative)
                        .accessibilityIdentifier("sync-problem")
                } footer: {
                    Text("Sync has been switched off, and everything is still saved on this device. Turn it on again to try once more.")
                }
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
                if isSyncingNow, let account = monitor.account.sentence {
                    Text(account)
                        .font(.footnote)
                        .foregroundStyle(Color.hoursNegative)
                }
                if isSyncingNow, let lastError = monitor.lastError {
                    // The system's own words, already in the phone's language.
                    Text(verbatim: lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

            #if DEBUG || CLOUDKIT_SCHEMA_TOOLS
            // Developer-only, never in an App Store build: see `CloudKitSchema`.
            Section {
                Button {
                    schemaOutcome = "…"
                    // Off the main thread: it waits on the network, and a
                    // screen frozen that long can be ended by the system.
                    Task.detached {
                        CloudKitSchema.initialize()
                        let outcome = CloudKitSchema.outcome
                        await MainActor.run { schemaOutcome = outcome }
                    }
                } label: {
                    Text(verbatim: "Initialise the CloudKit schema (Development)")
                }
                if let schemaOutcome {
                    Text(verbatim: schemaOutcome)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
        .task { await monitor.refreshAccount() }
        .paywall(for: $paywallReason)
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension SyncProblem {
    var sentence: String {
        switch self {
        case .notSignedForICloud:
            return String(localized: "Sync couldn't start: this copy of Zeitkonto isn't signed for iCloud.")
        case .signatureUnreadable:
            return String(localized: "Sync couldn't start: Zeitkonto couldn't confirm that this copy may use iCloud.")
        case .stoppedDuringLaunch:
            return String(localized: "Sync couldn't start: Zeitkonto stopped while connecting to iCloud last time.")
        case .storeRefused:
            return String(localized: "Sync couldn't start: iCloud wouldn't open the data on this device.")
        }
    }
}

private extension SyncMonitor.Account {
    /// Only what needs saying: an account that works says nothing.
    var sentence: String? {
        switch self {
        case .unknown, .available:
            return nil
        case .noAccount:
            return String(localized: "No iCloud account is signed in on this device, so nothing is being synced. Sign in in the Settings app and sync starts by itself.")
        case .restricted:
            return String(localized: "iCloud is restricted on this device, so nothing is being synced.")
        case .temporarilyUnavailable:
            return String(localized: "iCloud can't be reached right now. Sync carries on by itself when it can.")
        }
    }
}

#Preview {
    NavigationStack { SyncSettingsScreen() }
}
