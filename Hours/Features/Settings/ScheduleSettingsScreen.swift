import SwiftUI

/// The contracted week.
///
/// Hours are set per weekday rather than as one number, so an uneven week, a
/// four-day week or weekend work are all ordinary configurations rather than
/// things the app has to be argued into.
struct ScheduleSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    DurationStepperRow(
                        title: formatting.weekdayName(for: weekday),
                        minutes: weekdayBinding(weekday),
                        range: 0...(24 * 60),
                        step: 15,
                        formatting: settings.displayFormatting
                    )
                }
            } header: {
                Text("Contracted hours")
            } footer: {
                Text("A weekday set to zero is treated as a non-working day.")
            }

            Section {
                LabeledContent("Sum of the week") {
                    Text(settings.displayFormatting.string(settings.schedule.summedWeeklyMinutes))
                        .font(.hoursFigure(.body, weight: .medium))
                }
                Toggle("Different weekly target", isOn: weeklyOverrideToggle)
                if settings.schedule.weeklyTargetOverrideMinutes != nil {
                    DurationStepperRow(
                        title: "Weekly target",
                        minutes: weeklyOverrideBinding,
                        range: 0...(7 * 24 * 60),
                        step: 30,
                        formatting: settings.displayFormatting
                    )
                }
            } header: {
                Text("Weekly target")
            } footer: {
                Text("Use this when a contract states a weekly figure that does not divide evenly across the days.")
            }

            Section {
                OptionalTimeRow(
                    title: "Start",
                    time: defaultStartBinding,
                    calendar: calendar,
                    fallback: TimeOfDay(hour: 8, minute: 0)
                )
                OptionalTimeRow(
                    title: "End",
                    time: defaultEndBinding,
                    calendar: calendar,
                    fallback: TimeOfDay(hour: 16, minute: 30)
                )
                if settings.features.trackBreaks {
                    DurationStepperRow(
                        title: "Break",
                        minutes: defaultBreakBinding,
                        range: 0...(12 * 60),
                        step: 5,
                        formatting: settings.displayFormatting
                    )
                }
            } header: {
                Text("Defaults for a new day")
            } footer: {
                Text("These pre-fill the editor when you add hours to a working day. That comes to \(settings.displayFormatting.string(settings.schedule.defaultShiftMinutes)) worked.")
            }
        }
        .navigationTitle("Working schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var orderedWeekdays: [Int] { formatting.orderedWeekdayNumbers }

    // MARK: - Bindings

    private func weekdayBinding(_ weekday: Int) -> Binding<Int> {
        Binding(
            get: { settings.schedule.contractedMinutes(forWeekday: weekday) },
            set: { minutes in
                settingsStore.update { $0.schedule.setContractedMinutes(minutes, forWeekday: weekday) }
            }
        )
    }

    private var weeklyOverrideToggle: Binding<Bool> {
        Binding(
            get: { settings.schedule.weeklyTargetOverrideMinutes != nil },
            set: { isOn in
                settingsStore.update {
                    $0.schedule.weeklyTargetOverrideMinutes = isOn ? $0.schedule.summedWeeklyMinutes : nil
                }
            }
        )
    }

    private var weeklyOverrideBinding: Binding<Int> {
        Binding(
            get: { settings.schedule.weeklyTargetOverrideMinutes ?? 0 },
            set: { minutes in
                settingsStore.update { $0.schedule.weeklyTargetOverrideMinutes = minutes }
            }
        )
    }

    private var defaultStartBinding: Binding<TimeOfDay?> {
        Binding(
            get: { settings.schedule.defaultStart },
            set: { time in
                guard let time else { return }
                settingsStore.update { $0.schedule.defaultStart = time }
            }
        )
    }

    private var defaultEndBinding: Binding<TimeOfDay?> {
        Binding(
            get: { settings.schedule.defaultEnd },
            set: { time in
                guard let time else { return }
                settingsStore.update { $0.schedule.defaultEnd = time }
            }
        )
    }

    private var defaultBreakBinding: Binding<Int> {
        Binding(
            get: { settings.schedule.defaultBreakMinutes },
            set: { minutes in settingsStore.update { $0.schedule.defaultBreakMinutes = minutes } }
        )
    }
}
