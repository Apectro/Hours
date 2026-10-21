import SwiftUI

/// The contracted week for the main job.
///
/// With several jobs this edits the primary one; the others are edited from
/// Jobs, using the same controls.
struct ScheduleSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            WeekdayHoursSection(
                schedule: primarySchedule,
                formatting: settingsStore.dateFormatting,
                durationFormatting: settings.displayFormatting
            )

            ShiftDefaultsSection(
                schedule: primarySchedule,
                calendar: settingsStore.workCalendar,
                tracksBreaks: settings.features.trackBreaks,
                breaksArePaid: settings.primaryJob.breaksArePaid,
                durationFormatting: settings.displayFormatting
            )

            // Also on the job's own editor. Here too because this is where
            // someone with one job looks after their hours, and the footer
            // above, which the switch changes, is on this screen.
            if settings.features.trackBreaks {
                PaidBreaksSection(breaksArePaid: primaryBreaksArePaid)
            }

            if settings.tracksMultipleJobs {
                Section {
                    NavigationLink {
                        JobSettingsScreen()
                    } label: {
                        SettingsRow(title: String(localized: "All jobs"), value: "\(settings.activeJobs.count)", systemImage: "bag")
                    }
                } footer: {
                    Text("This screen edits \(settings.primaryJob.name). Every job keeps its own week.")
                }
            }
        }
        .navigationTitle(settings.tracksMultipleJobs ? settings.primaryJob.name : "Working schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settings: AppSettings { settingsStore.settings }

    /// Writes back to wherever the primary job's week currently lives — the
    /// top-level schedule while there is one job, the job itself once there
    /// are several.
    private var primarySchedule: Binding<WorkSchedule> {
        Binding(
            get: { settingsStore.settings.primarySchedule },
            set: { newValue in settingsStore.update { $0.setPrimarySchedule(newValue) } }
        )
    }

    /// The same, for the primary job's break rule.
    private var primaryBreaksArePaid: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.primaryJob.breaksArePaid },
            set: { newValue in settingsStore.update { $0.setPrimaryBreaksArePaid(newValue) } }
        )
    }
}
