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
    /// A new site can start with people from your other crews, ticked here
    /// and added when it is saved.
    @State private var candidates: [CrewCandidate] = []
    @State private var chosenCrew: Set<String> = []

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

                if isNew && !candidates.isEmpty {
                    Section {
                        ForEach(candidates) { candidate in
                            CrewCandidateRow(candidate: candidate, isSelected: chosenCrew.contains(candidate.id)) {
                                toggle(candidate)
                            }
                        }
                    } header: {
                        Text("Crew from your other sites")
                    } footer: {
                        Text("Tick the people who come along. Anyone else can be added from the site's crew later.")
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
            .task { loadCandidates() }
        }
    }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock)
    }

    /// In a task rather than in `body`: the repository's reads collapse
    /// duplicates, which writes.
    private func loadCandidates() {
        guard isNew else { return }
        let calendar = settingsStore.workCalendar
        candidates = repository.crewCandidates(
            for: draft.id,
            today: CalendarDate.today(in: calendar),
            calendar: calendar
        )
    }

    private func toggle(_ candidate: CrewCandidate) {
        if chosenCrew.contains(candidate.id) {
            chosenCrew.remove(candidate.id)
        } else {
            chosenCrew.insert(candidate.id)
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

        let store = repository
        store.upsert(site)
        if isNew {
            store.addCrew(candidates.filter { chosenCrew.contains($0.id) }, to: site.id)
        }
        // A renamed or archived site changes which card the widget shows.
        HoursStack.refreshWidget()
        // And what the note on the 1st says, or whether there is one.
        let context = modelContext
        let settings = settingsStore
        Task { await MonthlySheetRefresher.refresh(context: context, settingsStore: settings) }
        // An archived site's extra work is no longer counted as waiting.
        Task { await ExtraWorkReminderRefresher.refresh(context: context, settingsStore: settings) }
        dismiss()
    }
}
