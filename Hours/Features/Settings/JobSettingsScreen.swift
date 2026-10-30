import SwiftUI

/// Manages the places you work.
///
/// Stays out of the way until it is needed: with one job this screen is a
/// single row, and no job picker appears anywhere else in the app.
struct JobSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var editing: Job?
    @State private var isCreating = false
    @State private var paywallReason: ProFeature?

    var body: some View {
        List {
            Section {
                Text("For when you work more than one job, each with its own week, rate and colour.")
                    .foregroundStyle(.hoursSecondaryText)
            }

            Section {
                ForEach(activeJobs) { job in
                    jobButton(job)
                }
                Button {
                    // Only the *second* job is sold. One job is the app
                    // working as it always has, and every job already set up
                    // keeps working whatever happens to a subscription — the
                    // hours recorded against it are the person's, not ours.
                    if needsProForAnotherJob {
                        paywallReason = .multipleJobs
                    } else {
                        isCreating = true
                    }
                } label: {
                    Label("Add a job", systemImage: "plus")
                        .proLock(needsProForAnotherJob)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("jobs-add")
            } footer: {
                if needsProForAnotherJob {
                    Text("A second job is part of Zeitkonto Pro. The job you have keeps working either way.")
                } else {
                    Text("Each job keeps its own contracted week, so two jobs with different hours each get their own balance rather than sharing one.")
                }
            }

            if !archivedJobs.isEmpty {
                Section {
                    ForEach(archivedJobs) { job in
                        jobButton(job)
                    }
                } header: {
                    Text("Archived")
                }
            }
        }
        .paywall(for: $paywallReason)
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { job in
            JobEditor(job: job, isNew: false)
        }
        .sheet(isPresented: $isCreating) {
            JobEditor(job: Job(name: "", tint: .teal), isNew: true)
        }
    }

    private var activeJobs: [Job] { settingsStore.settings.resolvedJobs.filter { !$0.isArchived } }
    private var archivedJobs: [Job] { settingsStore.settings.resolvedJobs.filter(\.isArchived) }

    private func jobButton(_ job: Job) -> some View {
        Button {
            editing = job
        } label: {
            row(for: job)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jobs-row")
    }

    /// "Work · 40h over 5 days", and on the right "9,50 €/h · main".
    private func row(for job: Job) -> some View {
        HStack(spacing: Metrics.medium) {
            Circle()
                .fill(job.tint.color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName())
                    .foregroundStyle(job.isArchived ? Color.secondary : Color.primary)
                Text(summary(for: job))
                    .font(.caption)
                    .foregroundStyle(.hoursSecondaryText)
            }
            Spacer(minLength: Metrics.small)
            Text(value(for: job))
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func value(for job: Job) -> String {
        let settings = settingsStore.settings
        var parts: [String] = []
        if let rules = job.pay?.value(on: CalendarDate.today(in: settingsStore.workCalendar)) {
            parts.append(String(
                localized: "\(settings.money.string(rules.hourlyRateCents))/h",
                comment: "Settings, the hourly rate; the value is an amount of money, such as 9,50 €"
            ))
        }
        if job.isPrimary { parts.append(String(localized: "main", comment: "Settings › Jobs: the main job")) }
        return parts.joined(separator: " · ")
    }

    /// `resolvedJobs` always contains at least the primary job — settings with
    /// none synthesise one from the schedule — so anything added from here is
    /// by definition a second, which is the thing that is sold.
    private var needsProForAnotherJob: Bool {
        !subscriptions.allows(.multipleJobs)
    }

    private func summary(for job: Job) -> String {
        let schedule = job.schedule(on: CalendarDate.today(in: settingsStore.workCalendar))
        let weekly = settingsStore.settings.displayFormatting.string(schedule.weeklyTargetMinutes)
        let days = schedule.workingDaysPerWeek
        var parts = [String(inflected: "\(weekly) over ^[\(days) day](inflect: true)")]
        if job.isArchived { parts.append(String(localized: "archived")) }
        return parts.joined(separator: "  ·  ")
    }
}

/// Creates or edits one job.
struct JobEditor: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Job
    /// The week being edited, nil until something is. Kept apart from
    /// `draft` because it is today's week rather than the job's whole
    /// history, and saving it asks when it starts.
    @State private var week: WorkSchedule?
    @State private var isAskingWhen = false
    private let isNew: Bool

    init(job: Job, isNew: Bool) {
        // The first job's stored English "Work" is edited as the word the
        // screen shows; `save` stores it back as "Work" if left alone, so it
        // keeps following the app's language.
        var shown = job
        shown.name = job.displayName()
        _draft = State(initialValue: shown)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Colour") {
                    TintPicker(selection: $draft.tint)
                }

                WeekdayHoursSection(
                    schedule: editedWeek,
                    formatting: settingsStore.dateFormatting,
                    durationFormatting: settingsStore.settings.displayFormatting
                )

                ShiftDefaultsSection(
                    schedule: editedWeek,
                    calendar: settingsStore.workCalendar,
                    tracksBreaks: settingsStore.settings.features.trackBreaks,
                    breaksArePaid: draft.breaksArePaid,
                    durationFormatting: settingsStore.settings.displayFormatting
                )

                // Never behind the paywall: it changes how hours already
                // recorded add up, and those are the person's whether or not
                // they pay. Only a second job is sold.
                if settingsStore.settings.features.trackBreaks {
                    PaidBreaksSection(breaksArePaid: $draft.breaksArePaid)
                }

                // Its own screen, which saves as the working week does — from
                // a date — so a job has to exist before it can be paid.
                if !isNew {
                    Section {
                        NavigationLink {
                            PaySettingsScreen(jobID: draft.id, showsGeneralSettings: false)
                        } label: {
                            SettingsRow(title: String(localized: "Pay"), value: paySummary, systemImage: "banknote")
                        }
                    }
                }

                ScheduleHistorySection(
                    history: draft.schedules,
                    today: today,
                    formatting: settingsStore.dateFormatting,
                    durationFormatting: settingsStore.settings.displayFormatting,
                    onRemove: { date in
                        draft.schedules.removeChange(from: date)
                        week = nil
                    }
                )

                if !isNew {
                    Section {
                        Toggle("Archived", isOn: $draft.isArchived)
                    } footer: {
                        Text("An archived job keeps everything already recorded against it but stops expecting hours and stops being offered for new work.")
                    }

                    if canDelete {
                        Section {
                            Button("Delete job", role: .destructive, action: delete)
                        } footer: {
                            Text(String(
                                localized: "Hours already recorded against this job stay, and count towards \(settingsStore.settings.primaryJob.displayName()).",
                                comment: "Deleting a job; the value is the name of the job they move to"
                            ))
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New job" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("job-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: requestSave)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scheduleChangePrompt(
                isPresented: $isAskingWhen,
                history: draft.schedules,
                lock: settingsStore.settings.monthLock,
                calendar: settingsStore.workCalendar,
                formatting: settingsStore.dateFormatting
            ) { start in
                var job = draft
                if let week { job.schedules.change(to: week, from: start) }
                save(job)
            }
        }
    }

    private var today: CalendarDate { CalendarDate.today(in: settingsStore.workCalendar) }

    /// Read from the store rather than the draft: pay is saved by its own
    /// screen, and the draft was taken before that.
    private var paySummary: String {
        let settings = settingsStore.settings
        guard let rules = settings.job(draft.id).pay?.value(on: today) else {
            return String(localized: "Not set")
        }
        return String(
            localized: "\(settings.money.string(rules.hourlyRateCents)) an hour",
            comment: "Settings, the hourly rate; the value is an amount of money"
        )
    }

    /// Today's week, edited in place until Save.
    private var editedWeek: Binding<WorkSchedule> {
        Binding(
            get: { week ?? draft.schedule(on: today) },
            set: { week = $0 }
        )
    }

    /// A new job's week is simply its week; an existing job's changed week
    /// first asks when the change starts.
    private func requestSave() {
        guard let week, week != draft.schedule(on: today) else {
            save(draft)
            return
        }
        if isNew {
            var job = draft
            job.schedules = ScheduleHistory(week)
            save(job)
        } else {
            isAskingWhen = true
        }
    }

    /// The primary job is what everything else falls back to, so it stays.
    private var canDelete: Bool { !draft.isPrimary }

    private func save(_ edited: Job) {
        var job = edited
        job.name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if job.isPrimary && job.name == Job(id: Job.primaryID, name: Job.defaultName).displayName() {
            job.name = Job.defaultName
        }
        settingsStore.update { settings in
            if isNew {
                settings.addJob(job)
            } else if job.isPrimary && settings.jobs.isEmpty {
                // Still the single-job case: the schedule and the break rule
                // live at the top level.
                settings.primarySchedules = job.schedules
                settings.setPrimaryBreaksArePaid(job.breaksArePaid)
            } else {
                // Pay is saved by its own screen while this sheet is open, so
                // the stored pay wins over the draft's copy of it.
                settings.updateJob(id: job.id) { stored in
                    let pay = stored.pay
                    stored = job
                    stored.pay = pay
                }
            }
        }
        dismiss()
    }

    private func delete() {
        let id = draft.id
        settingsStore.update { $0.removeJob(id: id) }
        dismiss()
    }
}
