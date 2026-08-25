import SwiftUI

/// The contracted hours of a week, as seven steppers.
///
/// Extracted so the app's own schedule and each job's schedule are edited by
/// the same control rather than by two that drift apart.
struct WeekdayHoursSection: View {
    @Binding var schedule: WorkSchedule
    let formatting: CalendarFormatting
    var durationFormatting: DurationFormatting = .display
    var footer: String = "A weekday set to zero is treated as a non-working day."

    var body: some View {
        Section {
            ForEach(formatting.orderedWeekdayNumbers, id: \.self) { weekday in
                DurationStepperRow(
                    title: formatting.weekdayName(for: weekday),
                    minutes: binding(for: weekday),
                    range: 0...(24 * 60),
                    step: 15,
                    formatting: durationFormatting
                )
            }
        } header: {
            Text("Contracted hours")
        } footer: {
            Text(footer)
        }

        Section {
            LabeledContent("Sum of the week") {
                Text(durationFormatting.string(schedule.summedWeeklyMinutes))
                    .font(.hoursFigure(.body, weight: .medium))
            }
            Toggle("Different weekly target", isOn: overrideToggle)
            if schedule.weeklyTargetOverrideMinutes != nil {
                DurationStepperRow(
                    title: "Weekly target",
                    minutes: overrideBinding,
                    range: 0...(7 * 24 * 60),
                    step: 30,
                    formatting: durationFormatting
                )
            }
        } header: {
            Text("Weekly target")
        } footer: {
            Text("Use this when a contract states a weekly figure that does not divide evenly across the days.")
        }
    }

    private func binding(for weekday: Int) -> Binding<Int> {
        Binding(
            get: { schedule.contractedMinutes(forWeekday: weekday) },
            set: { schedule.setContractedMinutes($0, forWeekday: weekday) }
        )
    }

    private var overrideToggle: Binding<Bool> {
        Binding(
            get: { schedule.weeklyTargetOverrideMinutes != nil },
            set: { isOn in
                schedule.weeklyTargetOverrideMinutes = isOn ? schedule.summedWeeklyMinutes : nil
            }
        )
    }

    private var overrideBinding: Binding<Int> {
        Binding(
            get: { schedule.weeklyTargetOverrideMinutes ?? 0 },
            set: { schedule.weeklyTargetOverrideMinutes = $0 }
        )
    }
}

/// Start, end and break used to pre-fill a new day.
struct ShiftDefaultsSection: View {
    @Binding var schedule: WorkSchedule
    let calendar: Calendar
    var tracksBreaks: Bool = true
    var durationFormatting: DurationFormatting = .display

    var body: some View {
        Section {
            OptionalTimeRow(
                title: "Start",
                time: Binding(
                    get: { schedule.defaultStart },
                    set: { newValue in if let newValue { schedule.defaultStart = newValue } }
                ),
                calendar: calendar,
                fallback: TimeOfDay(hour: 8, minute: 0)
            )
            OptionalTimeRow(
                title: "End",
                time: Binding(
                    get: { schedule.defaultEnd },
                    set: { newValue in if let newValue { schedule.defaultEnd = newValue } }
                ),
                calendar: calendar,
                fallback: TimeOfDay(hour: 16, minute: 30)
            )
            if tracksBreaks {
                DurationStepperRow(
                    title: "Break",
                    minutes: Binding(
                        get: { schedule.defaultBreakMinutes },
                        set: { schedule.defaultBreakMinutes = $0 }
                    ),
                    range: 0...(12 * 60),
                    step: 5,
                    formatting: durationFormatting
                )
            }
        } header: {
            Text("Defaults for a new day")
        } footer: {
            Text("These pre-fill the editor when you add hours to a working day. That comes to \(durationFormatting.string(schedule.defaultShiftMinutes)) worked.")
        }
    }
}
