import SwiftUI

/// Manages the places you work.
///
/// Stays out of the way until it is needed: with one job this screen is a
/// single row, and no job picker appears anywhere else in the app.
struct JobSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var editing: Job?
    @State private var isCreating = false

    var body: some View {
        List {
            Section {
                ForEach(settingsStore.settings.resolvedJobs) { job in
                    Button {
                        editing = job
                    } label: {
                        row(for: job)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Each job keeps its own contracted week, so two jobs with different hours each get their own balance rather than sharing one.")
            }

            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Add a job", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { job in
            JobEditor(job: job, isNew: false)
        }
        .sheet(isPresented: $isCreating) {
            JobEditor(job: Job(name: "", tint: .teal), isNew: true)
        }
    }

    private func row(for job: Job) -> some View {
        HStack(spacing: Metrics.medium) {
            Circle()
                .fill(job.tint.color)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name)
                    .foregroundStyle(job.isArchived ? .secondary : .primary)
                Text(summary(for: job))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func summary(for job: Job) -> String {
        let weekly = settingsStore.settings.displayFormatting.string(job.schedule.weeklyTargetMinutes)
        let days = job.schedule.workingDaysPerWeek
        var parts = [String(localized: "\(weekly) over ^[\(days) day](inflect: true)")]
        if job.isArchived { parts.append("archived") }
        return parts.joined(separator: "  ·  ")
    }
}

/// Creates or edits one job.
struct JobEditor: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Job
    private let isNew: Bool

    init(job: Job, isNew: Bool) {
        _draft = State(initialValue: job)
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
                    schedule: $draft.schedule,
                    formatting: settingsStore.dateFormatting,
                    durationFormatting: settingsStore.settings.displayFormatting
                )

                ShiftDefaultsSection(
                    schedule: $draft.schedule,
                    calendar: settingsStore.workCalendar,
                    tracksBreaks: settingsStore.settings.features.trackBreaks,
                    durationFormatting: settingsStore.settings.displayFormatting
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
                            Text("Hours already recorded against this job stay, and count towards \(settingsStore.settings.primaryJob.name).")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New job" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// The primary job is what everything else falls back to, so it stays.
    private var canDelete: Bool { !draft.isPrimary }

    private func save() {
        var job = draft
        job.name = job.name.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.update { settings in
            if isNew {
                settings.addJob(job)
            } else if job.isPrimary && settings.jobs.isEmpty {
                // Still the single-job case: the schedule lives at the top level.
                settings.setPrimarySchedule(job.schedule)
            } else {
                settings.updateJob(id: job.id) { $0 = job }
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
