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
}
