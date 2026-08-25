import SwiftUI

/// The settings index.
///
/// Grouped by what you are changing rather than by which type holds it, and
/// each row says what it currently is, so the common case — checking a setting
/// — does not need a tap.
struct SettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Work") {
                    NavigationLink {
                        ScheduleSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Working schedule",
                            value: scheduleSummary,
                            systemImage: "calendar.badge.clock"
                        )
                    }
                    NavigationLink {
                        JobSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Jobs",
                            value: jobsSummary,
                            systemImage: "bag"
                        )
                    }
                    NavigationLink {
                        CalculationSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Calculation",
                            value: settings.durationPolicy.title,
                            systemImage: "function"
                        )
                    }
                }

                Section("Tracking") {
                    NavigationLink {
                        TrackingSettingsScreen()
                    } label: {
                        SettingsRow(title: "Fields", value: fieldsSummary, systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        DayTypeSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Day types",
                            value: "\(settings.dayTypeCatalog.all.count)",
                            systemImage: "tag"
                        )
                    }
                    NavigationLink {
                        ReminderSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Reminders",
                            value: settings.reminders.isEnabled ? "On" : "Off",
                            systemImage: "bell"
                        )
                    }
                    if settings.features.trackHolidays {
                        NavigationLink {
                            HolidaySettingsScreen()
                        } label: {
                            SettingsRow(title: "Holidays", value: nil, systemImage: "flag")
                        }
                    }
                }

                Section("Appearance") {
                    NavigationLink {
                        CalendarSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Calendar",
                            value: settings.calendar.showWeekends ? "All days" : "Weekdays only",
                            systemImage: "square.grid.3x3"
                        )
                    }
                    NavigationLink {
                        AppearanceSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Theme",
                            value: settings.appearance.title,
                            systemImage: "circle.lefthalf.filled"
                        )
                    }
                }

                Section("Export") {
                    NavigationLink {
                        ExportSettingsScreen()
                    } label: {
                        SettingsRow(
                            title: "Export options",
                            value: "\(settings.effectiveExportColumns.count) columns",
                            systemImage: "tablecells"
                        )
                    }
                }

                Section("Data") {
                    NavigationLink {
                        DataSettingsScreen()
                    } label: {
                        SettingsRow(title: "Backup and data", value: nil, systemImage: "externaldrive")
                    }
                    NavigationLink {
                        AboutScreen()
                    } label: {
                        SettingsRow(title: "Privacy", value: nil, systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var settings: AppSettings { settingsStore.settings }

    private var jobsSummary: String {
        let jobs = settings.activeJobs
        return jobs.count == 1 ? jobs[0].name : "\(jobs.count)"
    }

    private var scheduleSummary: String {
        let weekly = settings.primarySchedule.weeklyTargetMinutes
        let days = settings.primarySchedule.workingDaysPerWeek
        return "\(settings.displayFormatting.string(weekly)) over \(days) \(days == 1 ? "day" : "days")"
    }

    private var fieldsSummary: String {
        var enabled: [String] = []
        if settings.features.trackBreaks { enabled.append("breaks") }
        if settings.features.trackOvertime { enabled.append("overtime") }
        if settings.features.trackNotes { enabled.append("notes") }
        if settings.features.trackLocation { enabled.append("location") }
        if settings.features.trackTags { enabled.append("tags") }
        return enabled.isEmpty ? "None" : enabled.joined(separator: ", ").capitalizedFirstLetter
    }
}

/// A settings row: what it is on the left, what it is set to on the right.
struct SettingsRow: View {
    let title: String
    var value: String?
    var systemImage: String?

    var body: some View {
        HStack(spacing: Metrics.medium) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
            }
            Text(title)
            Spacer(minLength: Metrics.small)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
