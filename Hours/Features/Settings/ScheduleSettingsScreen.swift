import SwiftUI

/// The contracted week for the main job.
///
/// With several jobs this edits the primary one; the others are edited from
/// Jobs, using the same controls.
///
/// Edits collect in a draft rather than saving as they happen, because a
/// changed week now has a start: Save asks when the change begins, and only
/// then does anything move. The draft starts from the week in force today.
struct ScheduleSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    /// Nil until something is edited.
    @State private var draft: WorkSchedule?
    @State private var isAskingWhen = false

    var body: some View {
        Form {
            WeekdayHoursSection(
                schedule: editedSchedule,
                formatting: settingsStore.dateFormatting,
                durationFormatting: settings.displayFormatting
            )

            Section {
                // Also on the job's own editor. Here too because this is
                // where someone with one job looks after their hours.
                if settings.features.trackBreaks {
                    Toggle("Breaks are paid", isOn: primaryBreaksArePaid)
                        .accessibilityIdentifier("breaks-are-paid")
                }
                NavigationLink {
                    ScheduleChangesScreen()
                } label: {
                    LabeledContent("Changes over time") {
                        Text(verbatim: "\(changeCount)")
                    }
                }
                .accessibilityIdentifier("schedule-changes")
            } footer: {
                Text("Changed jobs or hours? Save the change “from a date” so older months keep their old hours.")
            }

            ShiftDefaultsSection(
                schedule: editedSchedule,
                calendar: settingsStore.workCalendar,
                tracksBreaks: settings.features.trackBreaks,
                breaksArePaid: settings.primaryJob.breaksArePaid,
                durationFormatting: settings.displayFormatting
            )

            if settings.tracksMultipleJobs {
                Section {
                    NavigationLink {
                        JobSettingsScreen()
                    } label: {
                        SettingsRow(title: String(localized: "All jobs"), value: "\(settings.activeJobs.count)", systemImage: "bag")
                    }
                } footer: {
                    Text("This screen edits \(settings.primaryJob.displayName()). Every job keeps its own week.")
                }
            }
        }
        .navigationTitle(settings.tracksMultipleJobs ? settings.primaryJob.displayName() : String(localized: "Working hours"))
        .navigationBarTitleDisplayMode(.inline)
        // Leaving with an unsaved week would quietly drop it, so while there
        // is one the way out is Discard or Save.
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { draft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { isAskingWhen = true }
                        .fontWeight(.semibold)
                }
            }
        }
        .scheduleChangePrompt(
            isPresented: $isAskingWhen,
            history: settings.primarySchedules,
            lock: settings.monthLock,
            calendar: settingsStore.workCalendar,
            formatting: settingsStore.dateFormatting
        ) { start in
            guard let draft else { return }
            settingsStore.update { $0.changePrimarySchedule(to: draft, from: start) }
            self.draft = nil
        }
    }

    private var settings: AppSettings { settingsStore.settings }

    private var today: CalendarDate { CalendarDate.today(in: settingsStore.workCalendar) }

    /// The week in force today, which is what the screen shows and edits.
    private var current: WorkSchedule { settings.primarySchedule(on: today) }

    private var hasChanges: Bool { draft.map { $0 != current } ?? false }

    private var changeCount: Int { max(0, settings.primarySchedules.versions.count - 1) }

    private var editedSchedule: Binding<WorkSchedule> {
        Binding(
            get: { draft ?? current },
            set: { draft = $0 }
        )
    }

    /// The primary job's break rule. Not part of the week, so it saves as it
    /// is switched: it changes how every recorded day adds up, the way it
    /// always has, rather than starting from a date.
    private var primaryBreaksArePaid: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.primaryJob.breaksArePaid },
            set: { newValue in settingsStore.update { $0.setPrimaryBreaksArePaid(newValue) } }
        )
    }
}

/// Working hours › Changes over time: each change of the week, newest
/// first, each of which can be taken back.
private struct ScheduleChangesScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let settings = settingsStore.settings
        List {
            if settings.primarySchedules.hasChanges {
                ScheduleHistorySection(
                    history: settings.primarySchedules,
                    today: CalendarDate.today(in: settingsStore.workCalendar),
                    formatting: settingsStore.dateFormatting,
                    durationFormatting: settings.displayFormatting,
                    onRemove: { date in
                        settingsStore.update { $0.primarySchedules.removeChange(from: date) }
                    }
                )
            } else {
                Section {
                    Text("No changes yet. When you save a new week, you choose the day it starts, and it shows here.")
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
        }
        .navigationTitle("Changes over time")
        .navigationBarTitleDisplayMode(.inline)
    }
}
