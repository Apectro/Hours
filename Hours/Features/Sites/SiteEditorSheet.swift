import SwiftUI
import SwiftData

/// A site's settings (the Settings button on its page; 1.2, mockup Sites):
/// its name, address and job; the usual day (times, break, work days ›);
/// the extras, the arrival reminder › and archiving. New
/// sites are made with the wizard (`NewSiteWizard`); this still creates one
/// when asked, starting from Settings › New sites start with.
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
    /// The other active sites, for the arrival reminder's limit of 20.
    @State private var otherSites: [Site] = []
    /// "Fill in from the saved place" is asking Apple Maps.
    @State private var isFindingAddress = false
    /// It asked, and Apple Maps had no address for the place.
    @State private var foundNoAddress = false
    /// The site's usual day and extras (1.2), kept in settings
    /// (`AppSettings.siteSetups`); read once when the sheet opens.
    @State private var setup = SiteSetup()
    @State private var loadedSetup = false

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
                    LabeledContent("Name") {
                        TextField("Name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("site-name")
                            .disabled(isReadOnly)
                    }
                    // 1.2: printed under the name on the site's sheets.
                    LabeledContent("Address") {
                        TextField("Address", text: $draft.address, axis: .vertical)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1...3)
                            .textInputAutocapitalization(.words)
                            .textContentType(.fullStreetAddress)
                            .accessibilityIdentifier("site-address")
                            .disabled(isReadOnly)
                    }
                    if let place = draft.place, !isReadOnly {
                        Button {
                            Task { await fillAddress(from: place) }
                        } label: {
                            HStack(spacing: Metrics.small) {
                                Text("Fill in from the saved place")
                                if isFindingAddress {
                                    Spacer(minLength: Metrics.small)
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isFindingAddress)
                        .accessibilityIdentifier("site-address-fill")
                    }
                    // Only for someone who tracks more than one job: with one
                    // there is nothing to choose.
                    if settingsStore.settings.tracksMultipleJobs {
                        Picker("Job", selection: jobBinding) {
                            ForEach(jobChoices) { job in
                                Text(job.displayName()).tag(job.id)
                            }
                        }
                        .disabled(isReadOnly)
                    }
                } footer: {
                    if isReadOnly {
                        Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                    } else if foundNoAddress {
                        Text("Apple Maps has no address for the saved place. Type it instead.")
                    } else if draft.place != nil {
                        Text("Printed under the site's name on its sheets. “Fill in from the saved place” asks Apple Maps for the address of that one place, only when you tap it.")
                    } else if settingsStore.settings.tracksMultipleJobs {
                        Text("The address is printed under the name on every sheet. The job is the one this site's hours count towards; days already recorded keep theirs.")
                    } else {
                        Text("Printed under the site's name on its sheets.")
                    }
                }

                usualDaySection

                Section {
                    // Only while the allowance is tracked (Settings › Allowance
                    // & travel); the site's own say, frozen on each day as
                    // written.
                    if settingsStore.settings.allowance.isEnabled {
                        Toggle("Field allowance by default", isOn: $draft.allowanceByDefault)
                            .accessibilityIdentifier("site-editor-allowance")
                            .disabled(isReadOnly)
                    }
                    SiteExtrasRows(
                        setup: $setup,
                        allowanceByDefault: $draft.allowanceByDefault,
                        showsAllowance: false,
                        isDisabled: isReadOnly
                    )
                    // The opt-in arrival reminder (1.2), on a page of its own:
                    // off unless turned on there.
                    NavigationLink(value: SiteEditorRoute.arrival) {
                        LabeledContent("Arrival reminder", value: arrivalSummary)
                    }
                    .accessibilityIdentifier("site-editor-arrival-row")
                    if !isNew {
                        Toggle("Archived", isOn: $draft.isArchived)
                            .accessibilityIdentifier("site-editor-archived")
                    }
                } header: {
                    Text("Extras")
                } footer: {
                    if !isNew {
                        Text("An archived site keeps every recorded day and its whole crew, and stops appearing among your active sites.")
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
            }
            .navigationTitle(isNew ? String(localized: "New site") : String(localized: "Site settings"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SiteEditorRoute.self) { route in
                switch route {
                case .arrival:
                    SiteArrivalScreen(site: $draft, isReadOnly: isReadOnly, otherSites: otherSites)
                case .workDays:
                    SiteWorkDaysScreen(days: $setup.workDays, isReadOnly: isReadOnly)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier("site-editor-save")
                }
            }
            .paywall(for: $paywallReason)
            .task {
                loadSetup()
                loadCandidates()
            }
        }
    }

    /// "150 m" while it is on, "Off" otherwise.
    private var arrivalSummary: String {
        draft.monitorsArrival ? SiteArrivalSection.metres(draft.monitoredRadius) : String(localized: "Off")
    }

    // MARK: - Usual day (1.2)

    @ViewBuilder
    private var usualDaySection: some View {
        Section {
            Toggle("Usual times", isOn: hasUsualTimes)
                .accessibilityIdentifier("site-editor-usual-times")
                .disabled(isReadOnly)
            if setup.hasUsualTimes {
                UsualDayRows(
                    start: timeBinding(\.start),
                    end: timeBinding(\.end),
                    breakMinutes: $setup.breakMinutes,
                    calendar: settingsStore.workCalendar,
                    isDisabled: isReadOnly,
                    combinesTimes: true
                )
            }
            NavigationLink(value: SiteEditorRoute.workDays) {
                LabeledContent("Work days", value: workDaysSummary)
            }
            .accessibilityIdentifier("site-editor-work-days")
        } header: {
            Text("Usual day")
        } footer: {
            Text("A new day on this site starts with these times for everyone ticked. Change any day or person as usual.")
        }
    }

    /// "Mon–Fri", or "As worked lately" with none ticked.
    private var workDaysSummary: String {
        SiteSetupText(
            formatting: settingsStore.dateFormatting,
            durations: settingsStore.settings.displayFormatting,
            calendar: settingsStore.workCalendar
        ).workDays(setup.workDays)
    }

    private var hasUsualTimes: Binding<Bool> {
        Binding(
            get: { setup.hasUsualTimes },
            set: { on in
                if on {
                    let today = CalendarDate.today(in: settingsStore.workCalendar)
                    let usual = settingsStore.settings.newSites.setup(
                        schedule: settingsStore.settings.primarySchedule(on: today)
                    )
                    setup.start = usual.start
                    setup.end = usual.end
                    setup.breakMinutes = usual.breakMinutes
                } else {
                    setup.start = nil
                    setup.end = nil
                    setup.breakMinutes = 0
                }
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<SiteSetup, TimeOfDay?>) -> Binding<TimeOfDay> {
        Binding(
            get: { setup[keyPath: keyPath] ?? TimeOfDay(hour: 7, minute: 0) },
            set: { setup[keyPath: keyPath] = $0 }
        )
    }

    /// The stored setup, or for a new site what new sites start with.
    private func loadSetup() {
        guard !loadedSetup else { return }
        loadedSetup = true
        let settings = settingsStore.settings
        if isNew {
            let today = CalendarDate.today(in: settingsStore.workCalendar)
            setup = settings.newSites.setup(schedule: settings.primarySchedule(on: today))
            draft.allowanceByDefault = settings.newSites.allowanceByDefault
        } else {
            setup = settings.siteSetup(for: draft.id)
        }
    }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock)
    }

    /// In a task rather than in `body`: the repository's reads collapse
    /// duplicates, which writes.
    private func loadCandidates() {
        otherSites = repository.sites(includeArchived: false).filter { $0.id != draft.id }
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

    /// Asks Apple Maps for the saved place's address, only on the tap, and
    /// puts it in the field to be checked or changed before saving.
    private func fillAddress(from place: SitePlace) async {
        isFindingAddress = true
        foundNoAddress = false
        let address = await HoursStack.arrivals.address(of: place)
        isFindingAddress = false
        if let address {
            draft.address = address
        } else {
            foundNoAddress = true
        }
    }

    private func save() {
        var site = draft
        site.name = trimmedName
        site.address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.name.isEmpty else { return }

        // Bringing a site back from the archive makes it active again, which
        // is the same thing as adding one as far as the free site goes.
        if wasArchived, !site.isArchived, !subscriptions.canAddSite(activeSites: otherActiveSites) {
            paywallReason = .multipleSites
            return
        }

        let store = repository
        store.upsert(site)
        if !isReadOnly {
            let setup = self.setup
            settingsStore.update { $0.setSiteSetup(setup, for: site.id) }
        }
        if isNew {
            store.addCrew(candidates.filter { chosenCrew.contains($0.id) }, to: site.id)
        }
        // A renamed or archived site changes which card the widget shows.
        HoursStack.refreshWidget()
        // And which sites are watched for the arrival reminder.
        HoursStack.arrivals.refresh()
        // And what the note on the 1st says, or whether there is one.
        let context = modelContext
        let settings = settingsStore
        Task { await MonthlySheetRefresher.refresh(context: context, settingsStore: settings) }
        // And the evening reminder, which follows its work days.
        Task {
            await SiteReminderRefresher.refresh(
                context: context,
                preferences: settings.settings.reminders,
                calendar: settings.workCalendar
            )
        }
        // An archived site's extra work is no longer counted as waiting.
        Task { await ExtraWorkReminderRefresher.refresh(context: context, settingsStore: settings) }
        dismiss()
    }
}

/// The pages the site's settings push: by value, inside the sheet's stack.
enum SiteEditorRoute: Hashable {
    case arrival
    case workDays
}

/// The days the site is worked, on a page of their own.
private struct SiteWorkDaysScreen: View {
    @Binding var days: Set<Int>
    let isReadOnly: Bool

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                WorkDaysPicker(days: $days, formatting: settingsStore.dateFormatting, isDisabled: isReadOnly)
            } footer: {
                Text("Reminders only nag on these days. With none ticked, they go by the days the site was worked lately.")
            }
        }
        .navigationTitle("Work days here")
        .navigationBarTitleDisplayMode(.inline)
    }
}
