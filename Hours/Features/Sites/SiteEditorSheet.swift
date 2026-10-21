import SwiftUI
import SwiftData

/// Creates a site, or renames, re-points and archives one.
///
/// The job picker only appears for someone who tracks more than one job: with
/// one job there is nothing to choose, and the site's hours count towards it
/// the way every other hour does.
struct SiteEditorSheet: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Site
    @State private var paywallReason: ProFeature?

    private let isNew: Bool
    /// One of the extra sites after Pro lapsed. Its name and job stay as they
    /// are, but archiving it is still allowed — archiving down to one active
    /// site is one of the two ways back.
    private let isReadOnly: Bool
    /// Active sites other than this one, which decides whether bringing it
    /// back from the archive is a second active site and so needs Pro.
    private let otherActiveSites: Int
    private let wasArchived: Bool

    init(site: Site, isNew: Bool, isReadOnly: Bool = false, otherActiveSites: Int = 0) {
        _draft = State(initialValue: site)
        self.isNew = isNew
        self.isReadOnly = isReadOnly
        self.otherActiveSites = otherActiveSites
        self.wasArchived = site.isArchived
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("site-name")
                        .disabled(isReadOnly)
                } footer: {
                    if isReadOnly {
                        Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                    }
                }

                if settingsStore.settings.tracksMultipleJobs {
                    Section {
                        Picker("Job", selection: jobBinding) {
                            ForEach(jobChoices) { job in
                                Text(job.name).tag(job.id)
                            }
                        }
                        .disabled(isReadOnly)
                    } footer: {
                        Text("The job this site's hours count towards. Days already recorded keep the job they were recorded with.")
                    }
                }

                if !isNew {
                    Section {
                        Toggle("Archived", isOn: $draft.isArchived)
                    } footer: {
                        Text("An archived site keeps every recorded day and its whole crew, and stops appearing among your active sites.")
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "New site") : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("site-editor-save")
                }
            }
            .paywall(for: $paywallReason)
        }
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` on the site means the primary job, so that is what the picker
    /// shows for it. A job that has gone since falls back the same way.
    private var jobBinding: Binding<UUID> {
        Binding(
            get: { settingsStore.settings.job(draft.jobID).id },
            set: { draft.jobID = $0 }
        )
    }

    /// The active jobs, plus the site's own if it has been archived since, so
    /// opening the editor never silently moves the site to another job.
    private var jobChoices: [Job] {
        let settings = settingsStore.settings
        var jobs = settings.activeJobs
        let current = settings.job(draft.jobID)
        if !jobs.contains(where: { $0.id == current.id }) {
            jobs.append(current)
        }
        return jobs
    }

    private func save() {
        var site = draft
        site.name = trimmedName
        guard !site.name.isEmpty else { return }

        // Bringing a site back from the archive makes it active again, which
        // is the same thing as adding one as far as the free site goes.
        if wasArchived, !site.isArchived, !subscriptions.canAddSite(activeSites: otherActiveSites) {
            paywallReason = .multipleSites
            return
        }

        SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock).upsert(site)
        // A renamed or archived site changes which card the widget shows.
        HoursStack.refreshWidget()
        dismiss()
    }
}
