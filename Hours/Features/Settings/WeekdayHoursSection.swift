import SwiftUI

/// The contracted hours of a week (1.2 redesign, board 15): one row a
/// day, "Mon  07:00–16:00 · 30m  8h 30m", a day off in grey, and the
/// week's total under them.
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
                WeekdayHoursRow(
                    weekday: weekday,
                    minutes: binding(for: weekday),
                    shift: shiftText,
                    formatting: formatting,
                    durationFormatting: durationFormatting
                )
            }
            LabeledContent("A week") {
                Text(durationFormatting.string(schedule.weeklyTargetMinutes))
                    .font(.hoursFigure(.body, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(minHeight: 44)
        } header: {
            Text("Your week")
        } footer: {
            Text(LocalizedStringKey(footer))
        }

        Section {
            Toggle("Different weekly target", isOn: overrideToggle)
            if schedule.weeklyTargetOverrideMinutes != nil {
                LabeledContent("Sum of the week") {
                    Text(durationFormatting.string(schedule.summedWeeklyMinutes))
                        .font(.hoursFigure(.body, weight: .medium))
                }
                DurationStepperRow(
                    title: String(localized: "Weekly target"),
                    minutes: overrideBinding,
                    range: 0...(7 * 24 * 60),
                    step: 30,
                    formatting: durationFormatting
                )
            }
        } footer: {
            Text("Use this when a contract states a weekly figure that does not divide evenly across the days.")
        }
    }

    /// "07:00–16:00 · 30m": the usual day a new day starts with.
    private var shiftText: String {
        let day = CalendarDate.today(in: formatting.calendar)
        let times = "\(formatting.time(schedule.defaultStart, on: day))–\(formatting.time(schedule.defaultEnd, on: day))"
        guard schedule.defaultBreakMinutes > 0 else { return times }
        return "\(times) · \(durationFormatting.string(schedule.defaultBreakMinutes))"
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

/// One day of the week: its short name, the usual times or "Day off" in
/// grey, the hours, and a stepper in quarter hours.
private struct WeekdayHoursRow: View {
    let weekday: Int
    @Binding var minutes: Int
    let shift: String
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting

    var body: some View {
        Stepper(value: $minutes, in: 0...(24 * 60), step: 15) {
            HStack(spacing: Metrics.medium) {
                Text(verbatim: formatting.shortWeekdaySymbol(for: weekday))
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 36, alignment: .leading)
                    .foregroundStyle(isWorking ? Color.primary : Color.secondary)
                if isWorking {
                    Text(verbatim: shift)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: Metrics.small)
                    Text(durationFormatting.string(minutes))
                        .font(.hoursFigure(.body, weight: .medium))
                } else {
                    Text("Day off")
                        .foregroundStyle(.hoursSecondaryText)
                    Spacer(minLength: Metrics.small)
                }
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel(Text(verbatim: formatting.weekdayName(for: weekday)))
        .accessibilityValue(isWorking ? Text(durationFormatting.string(minutes)) : Text("Day off"))
    }

    private var isWorking: Bool { minutes > 0 }
}

/// Start, end and break used to pre-fill a new day.
struct ShiftDefaultsSection: View {
    @Binding var schedule: WorkSchedule
    let calendar: Calendar
    var tracksBreaks: Bool = true
    /// The job's rule, so the footer's total is the one the day will show.
    var breaksArePaid: Bool = false
    var durationFormatting: DurationFormatting = .display

    var body: some View {
        Section {
            OptionalTimeRow(
                title: String(localized: "Start"),
                time: Binding(
                    get: { schedule.defaultStart },
                    set: { newValue in if let newValue { schedule.defaultStart = newValue } }
                ),
                calendar: calendar,
                fallback: TimeOfDay(hour: 8, minute: 0)
            )
            OptionalTimeRow(
                title: String(localized: "End"),
                time: Binding(
                    get: { schedule.defaultEnd },
                    set: { newValue in if let newValue { schedule.defaultEnd = newValue } }
                ),
                calendar: calendar,
                fallback: TimeOfDay(hour: 16, minute: 30)
            )
            if tracksBreaks {
                DurationStepperRow(
                    title: String(localized: "Break"),
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
            Text("Usual day")
        } footer: {
            Text(String(
                localized: "These pre-fill the editor when you add hours to a working day. That comes to \(durationFormatting.string(defaultWorkedMinutes)) worked.",
                comment: "Under the default start and end times; the value is the resulting length"
            ))
        }
    }

    /// With breaks switched off the engine takes nothing off a day, so the
    /// footer does not either. It used to subtract a default break that no
    /// day it described would ever lose.
    private var defaultWorkedMinutes: Int {
        schedule.defaultShiftMinutes(breaksArePaid: breaksArePaid || !tracksBreaks)
    }
}

/// Whether a job's employer pays for its breaks.
///
/// Its own section rather than a row under the defaults, because it changes
/// every day recorded against the job, not only how a new one is pre-filled.
/// Callers show it only while breaks are tracked: with breaks off nothing is
/// ever taken off, so the switch would do nothing.
struct PaidBreaksSection: View {
    @Binding var breaksArePaid: Bool

    var body: some View {
        Section {
            Toggle("Breaks are paid", isOn: $breaksArePaid)
                .accessibilityIdentifier("breaks-are-paid")
        } footer: {
            Text("Your break still gets written down, but it counts as worked time. Turn this on if your employer pays your breaks.")
        }
    }
}
